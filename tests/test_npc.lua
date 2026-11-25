local stub = require("stub")
local NW = require("npcworld")

-- The NPC window (Npc/): gossip and quests in one window, with the game's
-- own windows parked.

local function load(spec)
    spec = spec or {}
    stub.Load({ before = NW.world(spec), qol = spec.qol })
    local ns = stub.npc
    return ns.Window, ns
end

-- Advances one frame: server answers, deferred reads, the follower and moves.
local function frame(n)
    for _ = 1, n or 1 do
        stub.RunTimers()
        DaylightUI.Win.Followers.Tick()
        local d = DaylightUI.Win.Feel.Driver()
        if d then stub.RunOnUpdate(d, 1 / 30) end
        local m = DaylightUI.Motion.Driver()
        if m then stub.RunOnUpdate(m, 1 / 30) end
    end
end
local function settle() frame(30) end

local function texts(N)
    local out = {}
    for _, r in ipairs(N.rows or {}) do out[#out + 1] = r.text:GetText() end
    return out
end

local GOSSIP = { text = "Welcome to the inn.", options = { { name = "Make this inn your home.", icon = 1 }, { name = "Let me browse your goods.", icon = 2 } },
    available = { { title = "Kobold Candles", questLevel = 6, questID = 60 } }, active = {} }

T.test("npc: the game's gossip and quest windows are parked out of sight", function()
    local N = load()
    T.eq(GossipFrame:GetParent(), DaylightUI.Win.Followers.hidden)
    T.eq(QuestFrame:GetParent(), DaylightUI.Win.Followers.hidden)
    T.eq(GossipFrame:GetWidth(), 420, "the panel room: ours plus the gap, on the parked frame itself")
    T.isnil(NW.state.panel["GossipFrame.width"], "no layout attribute: it would taint the game's next ShowUIPanel")
    T.eq(N.frame:IsShown(), false)
end)

T.test("npc: a reward item loading late never runs the parked quest frame's reward code (ACTIVE_TEMPLATE error)", function()
    load()
    for _, mode in ipairs({ "DETAIL", "COMPLETE" }) do
        NW.Quest(mode, NW.Candles())
        frame(2)
        T.noerror(function() stub.FireEvent("QUEST_ITEM_UPDATE") end, mode)
    end
end)

T.test("npc: the first choice sits a little below the NPC's words", function()
    local N = load()
    NW.Gossip({ name = "Kyra Windblade", text = "Greetings.", options = { { name = "I require warrior training.", icon = 132058, orderIndex = 1 } } })
    frame()
    local said = N.frame.pages.talk.pieces[1]
    local gap = N.rows[1].stackY - said.stackY - said:GetHeight()
    T.eq(gap, 2 + N.SAID_GAP, "a row keeps its own 2 px")
end)

T.test("npc: the quest list sits below the NPC's words by the same extra gap", function()
    local N = load()
    NW.Gossip(GOSSIP)
    frame()
    local pieces = N.frame.pages.talk.pieces
    local said, head = pieces[1], pieces[2]
    T.eq(head.stackY - said.stackY - said:GetHeight(), 12 + N.SAID_GAP, "a section keeps its own 12 px")
end)

T.test("npc: a gossip opens ours with the NPC's name, text, quests then options, numbered", function()
    local N = load()
    NW.Gossip(GOSSIP)
    frame()
    T.eq(N.frame:IsShown(), true)
    T.eq(N.frame.title:GetText(), "William Pestle")
    T.eq(N.state.mode, "gossip")
    local t = texts(N)
    T.truthy(t[1]:find("Kobold Candles", 1, true), "the quest first")
    T.eq(t[2], "Make this inn your home.")
    T.eq(N.rows[3].key:GetText(), "3")
    settle()
    T.eq(N.frame:GetAlpha(), 1)
end)

T.test("npc: a quest page shows the quest's level after its name", function()
    local N = load()
    NW.Quest("DETAIL", NW.Candles({ level = 6 }))
    frame()
    local title = N.frame.pages.talk.pieces[1].text:GetText()
    T.truthy(title:find("Kobold Candles", 1, true), title)
    T.truthy(title:find("|c%x+6|r$"), "the level, in its color: " .. title)
end)

T.test("npc: a dungeon quest wears the tracker's tag in the list and under its title", function()
    local N = load()
    NW.tags[60] = 81
    NW.Gossip(GOSSIP)
    frame()
    local row = N.rows[1]
    T.truthy(row.tag and row.tag:IsShown(), "a tag on the quest's row")
    T.eq(row.tag.text:GetText(), "DUNGEON")
    T.truthy(not (N.rows[2].tag and N.rows[2].tag:IsShown()), "none on a gossip option")
    NW.Quest("DETAIL", NW.Candles({ level = 6 }))
    frame()
    local piece = N.frame.pages.talk.pieces[2]
    T.truthy(piece.tag, "a tag under the title")
    T.eq(piece.tag.text:GetText(), "DUNGEON")
end)

T.test("npc: a plain quest has no tag", function()
    local N = load()
    NW.Gossip(GOSSIP)
    frame()
    T.truthy(not (N.rows[1].tag and N.rows[1].tag:IsShown()))
end)

T.test("npc: a quest page the game has no level for takes the one the NPC's list gave", function()
    local N = load()
    NW.Gossip(GOSSIP)
    frame()
    NW.Quest("DETAIL", NW.Candles())
    frame()
    T.truthy(N.frame.pages.talk.pieces[1].text:GetText():find("|c%x+6|r$"), "the list's level 6")
    NW.Quest("DETAIL", NW.Candles({ questID = 61 }))
    frame()
    T.eq(N.frame.pages.talk.pieces[1].text:GetText(), "Kobold Candles", "no level known: the name alone")
end)

T.test("npc: a reward you can't use has a soft red icon, like the vendor's (the game's quest frame tints it too)", function()
    local N = load()
    NW.Quest("COMPLETE", NW.Candles({ choices = { { name = "Walking Boots", quality = 2 }, { name = "Plate Helm", quality = 2, usable = false } } }))
    frame()
    local r, g, b = N.tiles[1].icon:GetVertexColor()
    T.deq({ r, g, b }, { 1, 1, 1 }, "usable: untinted")
    r, g = N.tiles[2].icon:GetVertexColor()
    T.truthy(r > 0.85 and g < 0.25, "not for you: a red that shows on the art")
    local nr, ng = unpack(N.tiles[2].name.__textColor)
    T.truthy(nr > ng + 0.4, "and its name soft red")
    nr, ng = unpack(N.tiles[1].name.__textColor)
    T.truthy(ng > nr - 0.1, "a usable one keeps its quality color, not red")
end)

T.test("npc: a quest ready to hand in wears a gold ?, one under way a soft amber ring (the art is white)", function()
    local N = load()
    NW.Gossip({ text = "Back again?", options = {}, available = {},
        active = { { title = "The Gift of Skysight", questLevel = 4, questID = 61, isComplete = true },
                   { title = "Kobold Candles", questLevel = 6, questID = 60, isComplete = false } } })
    frame()
    local r, g, b = N.rows[1].icon:GetVertexColor()
    T.truthy(r > 0.9 and g > 0.7 and b < 0.4, "ready: gold")
    r, g, b = N.rows[2].icon:GetVertexColor()
    T.truthy(r > b + 0.2 and r < 0.9, "under way: soft amber")
    NW.Gossip(GOSSIP)
    frame()
    r, g, b = N.rows[2].icon:GetVertexColor()
    T.deq({ r, g, b }, { 1, 1, 1 }, "a reused row's option icon is untinted again")
end)

T.test("npc: picking an option uses its order index; picking a quest its id", function()
    local N = load()
    NW.Gossip(GOSSIP)
    frame()
    N.rows[3]:Click()
    T.deq(NW.Calls("SelectOptionByIndex"), { { 1 } })
    NW.Gossip(GOSSIP)
    frame()
    N.rows[1]:Click()
    T.deq(NW.Calls("SelectAvailableQuest"), { { 60 } })
end)

T.test("npc: gossip into a quest hands off in one window: no close, the page swaps", function()
    local N = load()
    NW.Gossip(GOSSIP)
    frame(); settle()
    N.rows[1]:Click()
    NW.CloseGossip(true)          -- the game: the talk goes on
    frame()
    T.eq(N.frame:IsShown(), true, "held")
    T.eq(N.state.closed.gossip, true)
    T.eq(#NW.Calls("CloseGossip"), 0, "the server closed it: not closed again")
    NW.Quest("DETAIL", NW.Candles())
    frame()
    T.eq(N.state.mode, "detail")
    T.eq(DaylightUI.Win.IsOpen(N.frame), true, "never closed in between")
    local page = N.frame.pages.talk
    T.eq(page:GetAlpha(), 1, "the dim ends as the next page comes")
end)

T.test("npc: a quest picked from a list has no button that talks to the NPC again (blocked InteractUnit)", function()
    -- Only the game's own UI may talk to an NPC: a Back button that did was refused
    -- with "blocked from an action only available to the Blizzard UI".
    for _, mode in ipairs({ "DETAIL", "PROGRESS", "COMPLETE" }) do
        local N = load()
        local function open()
            NW.Gossip(GOSSIP)
            frame(); settle()
            N.rows[1]:Click()
            NW.CloseGossip(true)
            NW.Quest(mode, NW.Candles())
            frame(); settle()
            return N.frame.pages.talk.foot.buttons
        end
        local n = 0
        for _, b in ipairs(open()) do if b:IsShown() then n = n + 1 end end
        for i = 2, n do open()[i]:Click() end
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
        T.eq(#NW.Calls("InteractUnit"), 0, mode)
        T.eq(n, 2, mode .. ": the main button and the way out, nothing between")
    end
end)

T.test("npc: a held hand-off that never comes closes softly", function()
    local N = load()
    local t = 100
    _G.GetTime = function() return t end
    NW.Gossip(GOSSIP)
    frame(); settle()
    N.rows[2]:Click()                 -- an option the game doesn't follow with a window of ours
    NW.CloseGossip(false)
    frame()
    T.eq(N.frame:IsShown(), true, "held a moment")
    t = t + 1
    stub.RunTimers()
    settle()
    T.eq(N.frame:IsShown(), false)
end)

T.test("npc: Escape: the game hides its window, we end the talk ourselves (its OnHide never runs)", function()
    local N = load()
    NW.Gossip(GOSSIP)
    frame(); settle()
    NW.Escape()
    frame()
    T.eq(#NW.Calls("CloseGossip"), 1)
    settle()
    T.eq(N.frame:IsShown(), false)
end)

T.test("npc: a PvP quest asks in Daylight UI's box first; yes accepts, no declines", function()
    local N = load()
    NW.Quest("DETAIL", NW.Candles({ pvp = true }))
    frame()
    T.eq(N.frame.pages.talk.foot:Press(1), true)
    T.eq(stub.Asked(), "pvpQuest", "asked, not the game's pop-up")
    T.eq(#NW.Calls("AcceptQuest"), 0, "nothing accepted yet")
    stub.Answer(true)
    T.eq(#NW.Calls("AcceptQuest"), 1)
    frame(); settle()
    NW.Quest("DETAIL", NW.Candles({ pvp = true }))
    frame()
    N.frame.pages.talk.foot:Press(1)
    T.eq(stub.Asked(), "pvpQuest")
    stub.Answer(false)
    T.eq(#NW.Calls("DeclineQuest"), 1)
    T.eq(#NW.Calls("AcceptQuest"), 1)
end)

T.test("npc: a quest offer: title, text, objectives, rewards; Accept accepts and the window closes", function()
    local N = load()
    NW.Quest("DETAIL", NW.Candles())
    frame()
    T.eq(N.state.mode, "detail")
    local foot = N.frame.pages.talk.foot
    T.eq(foot.buttons[1].text:GetText():match("^Accept") ~= nil, true)
    T.eq(foot:Press(1), true)
    T.eq(#NW.Calls("AcceptQuest"), 1)
    frame(); settle()
    T.eq(N.frame:IsShown(), false)
end)

T.test("npc: a quest from a poster (no NPC unit) shows the game's quest book, never an empty ring", function()
    local N = load()
    NW.Quest("DETAIL", NW.Candles())
    frame()
    T.eq(N.frame.portrait.__portraitUnit, "questnpc", "the quest window's unit, as QuestFrame_SetPortrait")
    T.eq(N.frame.portrait:IsShown(), true)
    N.Close(); settle()
    stub.SetUnits({ player = { name = "Daylight", class = "WARRIOR", level = 60, isPlayer = true } })
    N.frame.portrait.__portraitUnit = nil
    NW.Quest("DETAIL", NW.Candles())
    frame()
    T.eq(N.frame.portrait.__portraitUnit, nil)
    T.eq(N.frame.portrait:GetTexture(), "Interface\\QuestFrame\\UI-QuestLog-BookIcon")
    T.eq(N.frame.portrait:IsShown(), true)
    T.eq(N.frame.portraitRim:IsShown(), true)
end)

T.test("npc: an auto-accepted quest is acknowledged, never accepted again", function()
    local N = load()
    NW.Quest("DETAIL", NW.Candles({ auto = true }))
    frame()
    N.frame.pages.talk.foot:Press(1)
    T.eq(#NW.Calls("AcknowledgeAutoAcceptQuest"), 1)
    T.eq(#NW.Calls("AcceptQuest"), 0)
end)

T.test("npc: a quest started by an item never opens the window", function()
    local N = load()
    NW.Quest("DETAIL", NW.Candles(), 1234)
    frame(); settle()
    T.eq(N.frame:IsShown(), false)
end)

T.test("npc: hand-in: Complete waits for a choice, a number key picks, Space completes", function()
    local N = load()
    NW.Quest("COMPLETE", NW.Candles())
    frame()
    T.eq(N.state.mode, "reward")
    local foot = N.frame.pages.talk.foot
    T.eq(foot:Press(1), false, "no reward picked yet")
    T.eq(N.OnKey("2"), true)
    T.eq(N.state.choice, 2)
    T.eq(N.OnKey("SPACE"), true)
    T.deq(NW.Calls("GetQuestReward"), { { 2 } })
end)

-- First visit with Space spammed. The page arrives with no choices and they
-- come just after. A press in that gap must not hand in with no pick, or the
-- window closes and the game complains you must choose.
T.test("npc: hand-in: spammed Space on a reward page whose choices haven't come yet stays on it", function()
    local N = load()
    local q = NW.Candles()
    local late = q.choices
    q.choices = {}
    NW.Quest("COMPLETE", q)
    frame()
    for _ = 1, 3 do T.eq(N.OnKey("SPACE"), true, "kept from the game: no jump") end
    T.eq(#NW.Calls("GetQuestReward"), 0, "no choices known yet: nothing sent")
    q.choices = late   -- they come
    stub.FireEvent("QUEST_ITEM_UPDATE")
    frame()
    stub.Advance(N.REWARD_WAIT + 0.1)
    T.eq(#N.tiles, 3)
    N.OnKey("SPACE")
    T.eq(#NW.Calls("QuestChooseRewardError"), 1, "now it asks")
    T.eq(#NW.Calls("GetQuestReward"), 0)
    T.eq(N.state.mode, "reward")
end)

T.test("npc: hand-in: a reward page with no choices goes through once it has had its moment", function()
    local N = load()
    NW.Quest("COMPLETE", NW.Candles({ choices = {} }))
    frame()
    N.OnKey("SPACE")
    T.eq(#NW.Calls("GetQuestReward"), 0, "too soon to know")
    stub.Advance(N.REWARD_WAIT + 0.1)
    frame()
    T.eq(N.Buttons()[1].off, false, "the button is back")
    N.OnKey("SPACE")
    T.deq(NW.Calls("GetQuestReward"), { { 0 } })
end)

-- Only wait on a page that may still get choices. The quest log can say there
-- are none, so plain quests don't pause.
T.test("npc: hand-in: a quest the log says has no choices hands in at once", function()
    local N = load()
    NW.Quest("COMPLETE", NW.Candles({ choices = {}, log = { choices = 0 } }))
    frame()
    T.eq(N.Buttons()[1].off, false, "never shows as waiting")
    N.OnKey("SPACE")
    T.deq(NW.Calls("GetQuestReward"), { { 0 } })
    T.eq(#NW.Calls("RequestLoadQuestByID"), 0, "nothing to load")
end)

T.test("npc: hand-in: the log says choices are coming, or isn't loaded: the wait stays", function()
    for _, log in ipairs({ { choices = 3 }, { loading = true } }) do
        local N = load()
        NW.Quest("COMPLETE", NW.Candles({ choices = {}, log = log }))
        frame()
        N.OnKey("SPACE")
        T.eq(#NW.Calls("GetQuestReward"), 0)
        T.eq(N.state.mode, "reward")
    end
end)

-- The log has the quest but hasn't loaded it. Waiting half a second isn't an
-- answer, and a click must not send a blind 0 (the server replies "You don't
-- meet the requirements for that quest" and the window closes).
T.test("npc: hand-in: a blank page whose quest isn't loaded yet can't be handed in by a slow click", function()
    local N = load()
    local q = NW.Candles({ choices = {}, log = { loading = true } })
    NW.Quest("COMPLETE", q)
    frame()
    T.deq(NW.Calls("RequestLoadQuestByID"), { { q.questID } }, "the log is asked to load it")
    stub.Advance(N.REWARD_WAIT + 0.1)
    frame()
    N.OnKey("SPACE")
    T.eq(#NW.Calls("GetQuestReward"), 0, "still nothing known: nothing sent")
    T.eq(N.Buttons()[1].off, true, "and the button says so")
    q.log = { choices = 0 }   -- it loads, and there are none
    stub.Advance(N.WATCH_STEP + 0.01)
    frame()
    N.OnKey("SPACE")
    T.deq(NW.Calls("GetQuestReward"), { { 0 } })
end)

T.test("npc: hand-in: a quest that never loads doesn't hold the page shut", function()
    local N = load()
    NW.Quest("COMPLETE", NW.Candles({ choices = {}, log = { loading = true } }))
    frame()
    stub.Advance(N.WATCH_FOR + 0.2)
    frame()
    N.OnKey("SPACE")
    T.deq(NW.Calls("GetQuestReward"), { { 0 } })
end)

-- The page is not a snapshot: rewards that come in later show, with or without
-- an event.
T.test("npc: hand-in: rewards that come with no event show on the open page", function()
    local N = load()
    local q = NW.Candles()
    local late = q.choices
    q.choices = {}
    NW.Quest("COMPLETE", q)
    frame()
    q.choices = late   -- no QUEST_ITEM_UPDATE
    stub.Advance(N.WATCH_STEP + 0.01)
    frame()
    T.eq(#N.tiles, 3)
end)

T.test("npc: hand-in: the watch ends with the page's first seconds", function()
    local N = load()
    local q = NW.Candles({ choices = {} })
    NW.Quest("COMPLETE", q)
    frame()
    stub.Advance(N.WATCH_FOR + 1)
    frame()
    T.eq(N.watching, nil)
end)

-- The log knows there are choices and the page has none: never answer blind.
T.test("npc: hand-in: a blank page the log says has choices never sends an answer", function()
    local N = load()
    NW.Quest("COMPLETE", NW.Candles({ choices = {}, log = { choices = 3 } }))
    frame()
    stub.Advance(N.REWARD_WAIT + 1)
    T.eq(N.OnKey("SPACE"), true)
    T.eq(#NW.Calls("GetQuestReward"), 0)
    T.eq(N.Buttons()[1].off, true, "waiting, not asking for a pick with nothing to pick")
    T.eq(N.state.mode, "reward")
end)

-- Like the game's QuestRewardCompleteButton_OnClick: no pick while there are
-- choices gives QuestChooseRewardError, and the window stays.
T.test("npc: hand-in: Space with no reward picked says so and stays on the page", function()
    for _, look in ipairs({ "window", "immersive" }) do
        local N, ns = load()
        ns.module.db.look = look
        NW.Quest("COMPLETE", NW.Candles())
        frame(); settle()
        for _ = 1, 3 do T.eq(N.OnKey("SPACE"), true, "kept from the game: no jump") end
        frame(); settle()
        T.eq(#NW.Calls("QuestChooseRewardError"), 3, look)
        T.eq(#NW.Calls("GetQuestReward"), 0, look)
        T.eq(#NW.Calls("CloseQuest"), 0, look)
        T.eq(N.state.mode, "reward", look)
        T.eq(DaylightUI.Win.IsOpen(N.FrameFor("reward")), true, look)
        N.OnKey("2")
        N.OnKey("SPACE")
        T.deq(NW.Calls("GetQuestReward"), { { 2 } }, look)
    end
end)

-- The whole UI fades away in the immersive look: the game's words must not.
T.test("npc immersive: the game's error text stays while the UI is away", function()
    local N, ns = load()
    ns.module.db.look = "immersive"
    local e = CreateFrame("Frame", "UIErrorsFrame", UIParent)
    NW.Quest("COMPLETE", NW.Candles())
    frame(); settle()
    T.eq(UIParent:GetAlpha(), 0)
    T.eq(e:IsIgnoringParentAlpha(), true)
    N.Goodbye()
    settle()
    T.eq(e:IsIgnoringParentAlpha(), false, "its own flag given back")
end)

T.test("npc immersive: the card drags by its header and keeps its own spot; a right-click puts it back", function()
    local N, ns = load()
    ns.module.db.look = "immersive"
    NW.Quest("COMPLETE", NW.Candles())
    frame(); settle()
    local sc = N.scene
    T.truthy(sc:GetScript("OnDragStart"), "drags like the talk window")
    ns.Scene.spot.Save(400, -120)
    T.isnil(ns.module.db.spot, "the talk window's spot untouched")
    ns.Scene.Place()
    local p, rel = sc:GetPoint(1)
    T.eq(p, "TOP", "on the dragged spot")
    T.eq(rel, UIParent)
    T.truthy(ns.Scene.spot.Reset(), "a reset clears it")
    ns.Scene.Place()
    T.eq((sc:GetPoint(1)), "RIGHT", "back on the right")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game counts at the press; a list read earlier can be short.
T.test("npc: hand-in: choices that came after the page was read still need a pick", function()
    local N = load()
    local q = NW.Candles({ choices = {} })
    NW.Quest("COMPLETE", q)
    frame()
    q.choices = NW.Candles().choices
    N.OnKey("SPACE")
    T.eq(#NW.Calls("GetQuestReward"), 0, "never a hand-in with no pick")
    T.eq(#NW.Calls("QuestChooseRewardError"), 1)
    frame()
    T.eq(#N.tiles, 3, "and the page shows them")
    N.OnKey("3")
    N.OnKey("SPACE")
    T.deq(NW.Calls("GetQuestReward"), { { 3 } })
end)

T.test("npc: hand-in: double-clicking a reward picks it without handing the quest in", function()
    local N = load()
    NW.Quest("COMPLETE", NW.Candles())
    frame()
    local tile = N.tiles[2]
    tile:Click("LeftButton")
    -- In game a button with an OnDoubleClick script gets that instead of its second OnClick.
    tile:GetScript("OnDoubleClick")(tile, "LeftButton")
    T.eq(#NW.Calls("GetQuestReward"), 0, "no hand-in from a double-click")
    N.OnKey("SPACE")
    T.deq(NW.Calls("GetQuestReward"), { { 2 } }, "the double-clicked reward is the pick")
end)

-- Space tapped faster than the server answers: the old page is still up.
T.test("npc: one press per page: a second one before the next page sends nothing", function()
    local N = load()
    NW.Quest("PROGRESS", NW.Candles())
    frame()
    N.OnKey("SPACE")
    T.eq(N.OnKey("SPACE"), true, "still kept from the game")
    T.eq(#NW.Calls("CompleteQuest"), 1)
    NW.Quest("COMPLETE", NW.Candles())
    frame()
    N.OnKey("SPACE")
    T.eq(#NW.Calls("GetQuestReward"), 0)
    T.eq(#NW.Calls("QuestChooseRewardError"), 1, "the next page takes a press at once")
    NW.Gossip(GOSSIP)
    frame()
    N.OnKey("1")
    N.OnKey("1")
    T.eq(#NW.Calls("SelectAvailableQuest"), 1)
end)

-- The first visit to a hand-in can be slow: the next page can take longer than
-- Npc.HANDOFF. Spammed Space must not answer the old page again.
T.test("npc: a slow server: spammed Space never answers the same page twice", function()
    local N = load()
    NW.Quest("PROGRESS", NW.Candles())
    frame()
    N.OnKey("SPACE")
    stub.Advance(N.HANDOFF + 0.1)
    T.eq(N.OnKey("SPACE"), true, "still kept from the game")
    T.eq(#NW.Calls("CompleteQuest"), 1)
    NW.Quest("COMPLETE", NW.Candles())
    frame()
    N.OnKey("SPACE")
    T.eq(#NW.Calls("GetQuestReward"), 0)
    T.eq(#NW.Calls("QuestChooseRewardError"), 1)
    T.eq(N.state.mode, "reward")
end)

T.test("npc: a slow server: spammed Space doesn't press a gossip line twice", function()
    local N = load()
    NW.Gossip({ text = "Hello.", options = { { name = "Tell me more.", icon = 1 } } })
    frame()
    N.OnKey("SPACE")
    stub.Advance(N.HANDOFF + 0.1)
    T.eq(N.OnKey("SPACE"), true)
    T.eq(#NW.Calls("SelectOptionByIndex"), 1)
end)

-- Space walks through a talk, and spamming it is meant to work. Only an
-- unpicked reward stops it. Stopping on any list of two or more was tried and
-- felt worse.
T.test("npc: spamming Space walks the talk: the first line, the first quest, accept", function()
    local N = load()
    NW.Gossip({ text = "Hello.", options = { { name = "Tell me more.", icon = 1 }, { name = "Never mind.", icon = 2 } } })
    frame()
    T.eq(N.OnKey("SPACE"), true)
    T.eq(#NW.Calls("SelectOptionByIndex"), 1, "the first of two lines")
    NW.Gossip(GOSSIP)
    frame()
    N.OnKey("SPACE")
    T.deq(NW.Calls("SelectAvailableQuest"), { { 60 } })
    NW.Quest("DETAIL", NW.Candles())
    frame()
    N.OnKey("SPACE")
    T.eq(#NW.Calls("AcceptQuest"), 1)
end)

T.test("npc: one press per page: a server that never answers doesn't leave the page dead", function()
    local N = load()
    NW.Quest("PROGRESS", NW.Candles())
    frame()
    N.OnKey("SPACE")
    stub.Advance(N.ANSWER_WAIT + 0.1)
    N.OnKey("SPACE")
    T.eq(#NW.Calls("CompleteQuest"), 2)
end)

-- A choice whose item isn't loaded yet has no name from GetQuestItemInfo. It
-- still gets a tile so the picks keep the game's indexes.
T.test("npc: hand-in: an item still loading keeps its tile; the pick sends the game's index, kept over a refill", function()
    local N = load()
    local q = NW.Candles({ choices = { { quality = 2 }, { name = "Herbalist's Band", quality = 2 }, { name = "Mine Blade", quality = 1 } } })
    NW.Quest("COMPLETE", q)
    frame()
    T.eq(#N.tiles, 3, "the loading item is still a tile")
    T.eq(N.OnKey("3"), true)
    q.choices[1].name = "Walking Boots"   -- it loads
    stub.FireEvent("QUEST_ITEM_UPDATE")
    frame()
    T.eq(N.tiles[1].name:GetText(), "Walking Boots")
    T.eq(N.OnKey("SPACE"), true)
    T.deq(NW.Calls("GetQuestReward"), { { 3 } })
end)

T.test("npc: hand-in: choices the log promised that come long after the page still show", function()
    local N = load()
    local q = NW.Candles({ log = { choices = 3 } })
    local late = q.choices
    q.choices = {}
    NW.Quest("COMPLETE", q)
    frame()
    for _ = 1, 100 do stub.Advance(N.WATCH_STEP + 0.01); frame() end
    T.eq(N.RewardsStuck(), true, "says to talk again")
    q.choices = late
    stub.Advance(N.WATCH_STEP + 0.01)
    frame()
    T.eq(#N.tiles, 3)
    T.eq(N.RewardsStuck(), false)
    T.eq(N.Buttons()[1].text, "Choose a reward", "back to the normal page")
end)

-- Seen in game: the server's page came without the choices the log has, and
-- they never came (asking again with CompleteQuest brought nothing). Only
-- talking to the NPC again does, so after a moment the page says so and the
-- main button closes it, never sending an answer that can only fail.
T.test("npc: hand-in: a page that never gets the log's choices says so and closes on Space", function()
    local N = load()
    NW.Quest("COMPLETE", NW.Candles({ choices = {}, log = { choices = 2 } }))
    frame()
    T.eq(N.Buttons()[1].off, true, "waits at first")
    T.eq(N.RewardsStuck(), false)
    for _ = 1, math.ceil(N.STUCK_AFTER / N.WATCH_STEP) + 2 do stub.Advance(N.WATCH_STEP + 0.01); frame() end
    T.eq(N.RewardsStuck(), true)
    local b = N.Buttons()[1]
    T.eq(b.off, nil, "the main button works again")
    T.eq(b.text, CLOSE or "Close")
    T.eq(N.OnKey("SPACE"), true)
    T.eq(#NW.Calls("GetQuestReward"), 0, "no blind hand-in")
    T.eq(#NW.Calls("CloseQuest"), 1, "the talk ends, so the NPC can be asked again")
end)

-- The game's own reward window asks for an item it has no name for yet
-- (Item:CreateFromItemID(id):ContinueOnItemLoad) and fills it in when it comes.
-- Waiting on QUEST_ITEM_UPDATE alone left a slow item on "Retrieving item
-- information" for good.
T.test("npc: hand-in: a reward item that loads after the first seconds, with no event, still fills in", function()
    local N = load()
    local q = NW.Candles({ choices = { { itemID = 501, quality = 2 }, { name = "Herbalist's Band", quality = 2 } } })
    NW.Quest("COMPLETE", q)
    frame()
    T.deq(NW.Calls("ContinueOnItemLoad"), { { 501 } }, "the game is asked to load it")
    stub.Advance(N.WATCH_FOR + 1)
    frame()
    q.choices[1].name = "Walking Boots"   -- it loads, no QUEST_ITEM_UPDATE
    NW.LoadItem(501)
    frame()
    T.eq(N.tiles[1].name:GetText(), "Walking Boots")
    T.eq(#NW.Calls("ContinueOnItemLoad"), 1, "asked once for the page")
end)

-- The game's quest window reads every fixed reward as an item and only asks the loot
-- type for choices. Asking it for a fixed reward too sent a plain item down the
-- currency path, where it found nothing and stayed on "Retrieving item information".
T.test("npc: hand-in: a fixed reward is always an item, whatever its loot type says", function()
    local N = load()
    NW.Quest("COMPLETE", NW.Candles({ choices = {}, rewards = { { name = "Linen Cloth", itemID = 2589, lootType = 1 } } }))
    frame()
    local names = {}
    for _, p in ipairs(N.frame.pages[N.frame.current].pieces) do
        if p.spec and p.name then names[#names + 1] = p.name:GetText() end
    end
    T.deq(names, { "Linen Cloth" })
end)

-- A reward item loading late refills the page: once a frame, where you scrolled it.
T.test("npc: a late reward item refills the page once a frame and keeps the scroll", function()
    local N = load()
    local text = string.rep("A long story about candles and kobolds. ", 80)
    NW.Quest("COMPLETE", NW.Candles({ reward = text }))
    frame(); settle()
    local s = N.frame.pages.talk.stack
    T.truthy(s.height > s.scroll:GetHeight(), "a page longer than the window")
    s:ScrollTo(60)
    local fills, fill = 0, N.Fill
    N.Fill = function(...) fills = fills + 1; return fill(...) end
    stub.FireEvent("QUEST_ITEM_UPDATE")
    stub.FireEvent("QUEST_ITEM_UPDATE")
    T.eq(fills, 0, "not at once")
    frame()
    N.Fill = fill
    T.eq(fills, 1, "once a frame")
    T.eq(s:Scrolled(), 60, "still where you scrolled it")
end)

-- The coin: the choice worth the most at a vendor, a stack counted whole.
T.test("npc: the reward that sells for the most wears the coin, a stack counted whole", function()
    local N = load()
    NW.Quest("COMPLETE", NW.Candles({ choices = {
        { name = "Boots", sell = 100 }, { name = "Band", sell = 300 }, { name = "Potions", sell = 80, count = 5 } } }))
    frame()
    T.eq(N.tiles[1].mark:IsShown(), false)
    T.eq(N.tiles[2].mark:IsShown(), false, "300 loses to 5 x 80")
    T.eq(N.tiles[3].mark:IsShown(), true)
    T.eq(N.tiles[3].mark:GetTexture(), N.COIN)
end)

T.test("npc: no coin with nothing to tell apart: one choice, all the same, none sells", function()
    local N = load()
    for _, choices in ipairs({
        { { name = "Boots", sell = 100 } },
        { { name = "Boots", sell = 100 }, { name = "Band", sell = 100 } },
        { { name = "Boots", sell = 0 }, { name = "Band", sell = 0 } } }) do
        NW.Quest("COMPLETE", NW.Candles({ choices = choices }))
        frame()
        for _, b in ipairs(N.tiles) do T.eq(b.mark:IsShown(), false) end
    end
end)

-- It never lands on one item and moves: no coin until every price is known.
T.test("npc: the coin waits for every price, then a late one brings it", function()
    local N = load()
    local q = NW.Candles({ choices = { { name = "Boots", sell = 100 }, { name = "Band" } } })
    NW.Quest("COMPLETE", q)
    frame()
    T.eq(N.tiles[1].mark:IsShown(), false, "Band's price isn't known yet")
    T.eq(N.OnKey("2"), true)
    q.choices[2].sell = 300
    stub.FireEvent("GET_ITEM_INFO_RECEIVED")
    frame()
    T.eq(N.tiles[1].mark:IsShown(), false)
    T.eq(N.tiles[2].mark:IsShown(), true)
    T.eq(N.tiles[2].picked, true, "the pick holds")
end)

-- GET_ITEM_INFO_RECEIVED fires as you hover: a page waiting for nothing doesn't rebuild.
T.test("npc: an item loading elsewhere doesn't rebuild a page with its prices known", function()
    load()
    NW.Quest("COMPLETE", NW.Candles({ choices = { { name = "Boots", sell = 100 }, { name = "Band", sell = 300 } } }))
    frame()
    local Data, read = stub.npc.Data, 0
    local q = Data.Quest
    Data.Quest = function(...) read = read + 1; return q(...) end
    stub.FireEvent("GET_ITEM_INFO_RECEIVED")
    frame()
    Data.Quest = q
    T.eq(read, 0)
end)

T.test("npc: a tile handed to another item drops its coin", function()
    local N = load()
    NW.Quest("COMPLETE", NW.Candles({ choices = { { name = "Boots", sell = 900 }, { name = "Band", sell = 300 } } }))
    frame()
    local b = N.tiles[1]
    T.eq(b.mark:IsShown(), true)
    NW.Quest("COMPLETE", NW.Candles({ choices = { { name = "Cloak", sell = 100 }, { name = "Ring", sell = 300 } } }))
    frame()
    T.eq(b.name:GetText(), "Cloak")
    T.eq(b.mark:IsShown(), false)
end)

T.test("npc: a single reward is picked for you; a quest that costs money asks first", function()
    local N = load()
    NW.Quest("COMPLETE", NW.Candles({ choices = { { name = "Only", quality = 2 } }, cost = 500 }))
    frame()
    T.eq(N.state.choice, 1)
    N.OnKey("SPACE")
    T.eq(#NW.Calls("GetQuestReward"), 0, "asked first")
    T.truthy(N.frame.pages.talk.foot.buttons[1].text:GetText():find("Pay", 1, true))
    N.OnKey("SPACE")
    T.deq(NW.Calls("GetQuestReward"), { { 1 } })
end)

T.test("npc: progress: Continue only when the quest can be handed in; Space never jumps meanwhile", function()
    local N = load()
    NW.Quest("PROGRESS", NW.Candles({ completable = false }))
    frame()
    T.eq(N.OnKey("SPACE"), true, "kept from the game: no jump")
    T.eq(#NW.Calls("CompleteQuest"), 0)
    NW.Quest("PROGRESS", NW.Candles())
    frame()
    N.OnKey("SPACE")
    T.eq(#NW.Calls("CompleteQuest"), 1)
end)

T.test("npc: keys: 1 picks the first line, Escape says goodbye, other keys go on to the game", function()
    local N = load()
    NW.Gossip(GOSSIP)
    frame()
    T.eq(N.OnKey("W"), false)
    T.eq(N.OnKey("1"), true)
    T.deq(NW.Calls("SelectAvailableQuest"), { { 60 } })
    NW.Gossip(GOSSIP)
    frame()
    T.eq(N.OnKey("ESCAPE"), true)
    T.eq(#NW.Calls("CloseGossip"), 1)
end)

T.test("npc: keys switched off: no numbers shown, no keys taken", function()
    local N, ns = load()
    ns.module.db.keys = false
    NW.Gossip(GOSSIP)
    frame()
    T.eq(N.rows[1].key:IsShown(), false)
    T.eq(N.OnKey("1"), false)
end)

T.test("npc: Space by default (the button says so); Enter goes on to the game (chat)", function()
    local N = load()
    NW.Quest("DETAIL", NW.Candles())
    frame()
    T.truthy(N.frame.pages.talk.foot.buttons[1].text:GetText():find("Space", 1, true))
    T.eq(N.OnKey("ENTER"), false)
    T.eq(N.OnKey("SPACE"), true)
end)

T.test("npc: the window behind a pop-up lets its key through", function()
    local N, ns = load()
    NW.Quest("DETAIL", NW.Candles())
    frame()
    ns.Popups.space = true
    T.eq(N.OnKey("SPACE"), false, "Space is the box's: a key the window takes never reaches a binding")
    ns.Popups.space = false
    T.eq(N.OnKey("SPACE"), true, "and the window's again")
end)

T.test("npc: Enter only, when asked: Space still never jumps while talking", function()
    local N, ns = load()
    ns.module.db.acceptKey = "enter"
    NW.Quest("DETAIL", NW.Candles())
    frame()
    T.eq(N.OnKey("SPACE"), true)
    T.eq(#NW.Calls("AcceptQuest"), 0)
    T.eq(N.OnKey("ENTER"), true)
    T.eq(#NW.Calls("AcceptQuest"), 1)
end)

T.test("npc: a page another feature answered by itself never flashes up", function()
    local N = load()
    DaylightUI.TalkAnswered("QUEST_DETAIL")
    NW.Quest("DETAIL", NW.Candles())
    frame(); settle()
    T.eq(N.frame:IsShown(), false)
end)

T.test("npc: the sample talk works without an NPC and calls nothing of the game", function()
    local N = load()
    N.Sample()
    settle()
    T.eq(N.frame:IsShown(), true)
    N.OnKey("1")
    T.eq(N.state.mode, "detail")
    N.OnKey("SPACE")
    settle()
    T.eq(N.frame:IsShown(), false)
    T.eq(#NW.state.calls, 0)
end)

T.test("npc: switched off: the game's windows stay the game's", function()
    stub.Load({ before = function()
        NW.world()()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { NPC = { enabled = false } } } } }
    end })
    T.eq(GossipFrame:GetParent(), UIParent)
    T.isnil(stub.npc.Window.frame)
end)

local function loadOff()
    stub.Load({ before = function()
        NW.world()()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { NPC = { enabled = false } } } } }
    end })
    return stub.npc.Window
end

T.test("npc: the header's swap icon hands the talk to the game's window and it stays picked", function()
    local N = load()
    NW.Gossip(GOSSIP)
    frame()
    T.truthy(DaylightUI.Win.IsOpen(N.frame))
    T.truthy(N.frame.swap and N.frame.swap:IsShown(), "the swap icon sits in the header")
    T.truthy(N.scene.swap, "the immersive card has it too")
    N.frame.swap:Click()
    frame(10)
    T.eq(DaylightUI:Get("NPC", "enabled"), false, "the pick is saved")
    T.eq(DaylightUI.npcOwnWindow, false)
    T.falsy(DaylightUI.Win.IsOpen(N.frame), "ours steps aside")
    T.eq(GossipFrame:GetParent(), UIParent, "the game's gossip is back")
    T.truthy(GossipFrame:IsVisible(), "and shows the same talk")
    T.eq(#NW.Calls("CloseGossip"), 0, "the talk goes on there")
    T.truthy(N.swap.link:IsShown(), "with its way back")
    T.falsy(N.Covers("gossip"), "the skins may dress it")
    T.eq(QuestFrame:GetParent(), UIParent, "the closed quest window is let go too")
    T.eq(MerchantFrame:GetParent(), UIParent)
    NW.CloseGossip()
    frame(10)
    T.eq(GossipFrame:GetParent(), UIParent, "never parked while it's the pick")
    NW.Quest("DETAIL", NW.Candles())
    frame(); settle()
    T.falsy(DaylightUI.Win.IsOpen(N.frame), "the next talk opens in the game's window")
    T.truthy(QuestFrame:IsVisible())
    T.truthy(N.links[1].link:IsShown(), "the quest window has the way back too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("npc: switched off, the game's vendor's link switches back to Daylight UI's at once", function()
    local N = loadOff()
    T.isnil(N.frame, "nothing built while the game's are picked")
    NW.Merchant()
    frame()
    T.eq(MerchantFrame:GetParent(), UIParent)
    local link = N.links[2].link
    T.truthy(link and link:IsShown(), "the game's vendor has the switch")
    T.eq(link:GetParent(), MerchantFrame, "it rides on the game's window")
    T.falsy(N.swap.link:IsVisible(), "the gossip one shows with its own window")
    link:Click()
    frame(); settle()
    T.eq(DaylightUI:Get("NPC", "enabled"), true, "the pick is saved")
    T.truthy(N.frame and DaylightUI.Win.IsOpen(N.frame), "ours takes over the open vendor")
    T.eq(N.state.mode, "merchant")
    T.eq(MerchantFrame:GetParent(), DaylightUI.Win.Followers.aside, "the game's vendor is held aside")
    T.isnil(stub.ClipAncestor(MerchantFrame), "never under a clipping frame")
    T.eq(#NW.Calls("CloseMerchant"), 0, "still the same vendor")
    T.falsy(link:IsShown(), "the link is gone with the game's look")
    T.truthy(N.Covers("merchant"))
    T.eq(GossipFrame:GetParent(), DaylightUI.Win.Followers.hidden, "the closed gossip is parked")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("npc: switched back mid-gossip, the game's gossip finishes the talk and the next one is ours", function()
    local N = loadOff()
    NW.Gossip(GOSSIP)
    frame()
    T.truthy(GossipFrame:IsVisible())
    N.swap.link:Click()
    frame(); settle()
    T.eq(DaylightUI:Get("NPC", "enabled"), true)
    T.eq(GossipFrame:GetParent(), UIParent, "hiding it would end the talk")
    T.falsy(DaylightUI.Win.IsOpen(N.frame))
    T.eq(#NW.Calls("CloseGossip"), 0)
    T.falsy(N.Covers("gossip"), "still dressed while it shows as itself")
    NW.CloseGossip()
    frame(5)
    T.eq(GossipFrame:GetParent(), DaylightUI.Win.Followers.hidden, "parked once it closed")
    NW.Gossip(GOSSIP)
    frame()
    T.truthy(DaylightUI.Win.IsOpen(N.frame), "the next talk is ours")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("npc: the options switch trades the windows live, a shown vendor included", function()
    local N = load()
    NW.Merchant()
    frame()
    T.truthy(DaylightUI.Win.IsOpen(N.frame))
    DaylightUI:Set("NPC", "enabled", false)
    frame(10)
    T.falsy(DaylightUI.Win.IsOpen(N.frame))
    T.eq(MerchantFrame:GetParent(), UIParent)
    T.truthy(MerchantFrame:IsVisible())
    T.eq(#NW.Calls("CloseMerchant"), 0, "the same vendor, in the game's window")
    T.truthy(N.links[2].link:IsShown())
    T.falsy(N.Covers("trainer"), "the game's trainer gets its look when it opens")
    DaylightUI:Set("NPC", "enabled", true)
    frame(); settle()
    T.truthy(DaylightUI.Win.IsOpen(N.frame), "and back")
    T.eq(MerchantFrame:GetParent(), DaylightUI.Win.Followers.aside)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("npc skins: the game's talk windows wear the Daylight UI look only while they show as themselves", function()
    stub.Load({ skins = true, before = NW.world() })
    stub.RunTimers()
    local Kit, N = stub.skins.Kit, stub.npc.Window
    T.isnil(Kit.ShellOf(GossipFrame), "covered by Daylight UI's: nothing walked")
    T.isnil(Kit.ShellOf(QuestFrame))
    NW.Gossip(GOSSIP)
    frame()
    N.frame.swap:Click()
    frame(10)
    stub.RunTimers()
    T.truthy(Kit.ShellOf(GossipFrame), "handed over open, it's dressed then")
    NW.CloseGossip()
    frame(5)
    NW.Quest("DETAIL", NW.Candles())
    frame(); stub.RunTimers()
    T.truthy(Kit.ShellOf(QuestFrame), "the next game window is dressed as it opens")
    NW.Merchant()
    frame(); stub.RunTimers()
    T.truthy(Kit.ShellOf(MerchantFrame))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("npc: QoL's auto accept answers the offer: our window never opens for it", function()
    local N, ns = load({ qol = true })
    local q = DaylightUI:GetModule("QoL").db
    q.questAccept = true
    _G.IsShiftKeyDown = function() return false end
    NW.Quest("DETAIL", NW.Candles())
    frame(); settle()
    T.eq(#NW.Calls("AcceptQuest"), 1)
    T.eq(N.frame:IsShown(), false)
end)

T.test("npc: in combat the window still works by mouse, the keys are the game's, nothing protected is touched", function()
    local N = load()
    stub.secure = true
    stub.EnterCombat()
    NW.Gossip(GOSSIP)
    frame(); settle()
    T.eq(N.frame:IsShown(), true)
    local k = N.frame.keys
    k:GetScript("OnKeyDown")(k, "1")
    T.eq(#NW.Calls("SelectAvailableQuest"), 0, "keys go to the game in a fight (your action bar 1)")
    N.rows[1]:Click()
    T.deq(NW.Calls("SelectAvailableQuest"), { { 60 } })
    NW.CloseGossip(true)
    NW.Quest("COMPLETE", NW.Candles())
    frame()
    N.Pick(1)
    N.Complete()
    T.deq(NW.Calls("GetQuestReward"), { { 1 } })
    frame(); settle()
    T.eq(N.frame:IsShown(), false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.LeaveCombat()
    stub.secure = false
end)

T.test("npc: the game's window opened before it could be parked (a fight at login) stays the game's", function()
    local N = load({ before = function() GossipFrame:Show() end })
    T.eq(GossipFrame:GetParent(), UIParent)
    NW.Gossip(GOSSIP)
    frame()
    T.eq(N.frame:IsShown(), false, "ours stays out of it")
    GossipFrame:Hide()
    frame()
    T.eq(GossipFrame:GetParent(), DaylightUI.Win.Followers.hidden, "parked once it closed")
end)

-- ---------------------------------------------------------------------
-- The vendor page (Shop.lua)
-- ---------------------------------------------------------------------

local function shop(N) return N.frame.pages.shop end
local function tileNames(N)
    local out = {}
    for _, p in ipairs(shop(N).pieces) do if p.name then out[#out + 1] = p.name:GetText() end end
    return out
end

T.test("npc shop: a vendor opens the shelf, wider, with your money in the header, and opens your bags", function()
    local N = load()
    NW.Merchant({ junk = 2, repair = 160 })
    frame()
    T.eq(N.state.mode, "merchant")
    T.eq(N.frame.current, "shop")
    T.eq(N.frame:GetWidth(), 520)
    T.eq(N.frame.money:IsShown(), true)
    T.truthy(N.frame.money:GetText() ~= "")
    T.deq(NW.Calls("OpenAllBags"), { { "MerchantFrame" } }, "as the game's own OnShow would")
    T.eq(#NW.Calls("ResetSetMerchantFilter"), 1)
    T.eq(tileNames(N)[1], "Refreshing Spring Water")
end)

T.test("npc shop: gossip into the shop is one window: no close, it glides wider", function()
    local N = load()
    NW.Gossip({ text = "Need supplies?", options = { { name = "Let me browse your goods.", icon = 1 } } })
    frame(); settle()
    T.eq(N.frame:GetWidth(), 400)
    N.rows[1]:Click()
    NW.CloseGossip(true)
    frame()
    T.eq(N.frame:IsShown(), true, "held")
    NW.Merchant()
    frame()
    T.eq(N.state.mode, "merchant")
    T.eq(DaylightUI.Win.IsOpen(N.frame), true, "never closed in between")
    T.truthy(N.frame:GetWidth() < 520, "gliding, not jumping")
    settle()
    T.eq(N.frame:GetWidth(), 520)
end)

-- Seen in game: scrolled down the shelf, the list jumped back to the top as the
-- mouse moved over it. A hovered item's tooltip loads its info, which fires
-- GET_ITEM_INFO_RECEIVED and refills the shelf.
T.test("npc shop: a refill keeps the shelf where you scrolled it; a new search starts at the top", function()
    local N = load()
    local goods = {}
    for i = 1, 40 do goods[i] = { name = "Ware " .. i, price = 10 } end
    NW.Merchant({ items = goods })
    frame(); settle()
    local s = shop(N).stack
    T.truthy(s.height > s.scroll:GetHeight(), "a shelf longer than the window")
    s:ScrollTo(120)
    T.eq(s:Scrolled(), 120)
    stub.FireEvent("GET_ITEM_INFO_RECEIVED", 1, true)
    frame()
    T.eq(s:Scrolled(), 120, "still where you scrolled it")
    shop(N).search:SetText("Ware 3")
    frame()
    T.eq(s:Scrolled(), 0, "a new search reads from the top")
end)

-- Seen in game: the shelf filled while the window was still talk-wide, so
-- the tiles came out sized for 400 and stayed narrow in the 520 window.
T.test("npc shop: the tiles fill the wide window, opened fresh or from gossip", function()
    local function tileW(N)
        for _, p in ipairs(shop(N).pieces) do if p.spec then return p:GetWidth() end end
    end
    local P = DaylightUI.Win.Parts
    local want = function(N) return math.floor((N.frame:GetWidth() - 2 * P.EDGE - P.GAP) / 2) end
    local N = load()
    NW.Merchant()
    frame(); settle()
    T.eq(tileW(N), want(N), "fresh")
    N = load()
    NW.Gossip({ text = "Need supplies?", options = { { name = "Let me browse your goods.", icon = 1 } } })
    frame(); settle()
    N.rows[1]:Click()
    NW.CloseGossip(true)
    frame()
    NW.Merchant()
    frame(); settle()
    T.eq(tileW(N), want(N), "after the glide")
end)

T.test("npc shop: clicking fast buys on every click (the game turns a quick second click into a double-click)", function()
    local N = load()
    NW.Merchant()
    frame()
    local tile
    for _, p in ipairs(shop(N).pieces) do if p.spec then tile = p break end end
    tile:Click("LeftButton")
    -- In game a button with an OnDoubleClick script gets that instead of its second OnClick.
    tile:GetScript("OnDoubleClick")(tile, "LeftButton")
    T.eq(#NW.Calls("BuyMerchantItem"), 2, "both clicks bought")
end)

T.test("npc shop: buying stacks stops when another item moves into the slot", function()
    local _, ns = load()
    NW.Merchant()
    frame()
    local it = { index = 1, stack = 5, price = 25 }
    local max, most = ns.Shop.MaxOf(it)
    T.truthy(most >= max * 3, "room and money for three purchases")
    ns.Shop.BuyLots(it, max * 3)
    stub.RunTimers()
    T.eq(#NW.Calls("BuyMerchantItem"), 3, "a lot at a time, all three")
    ns.Shop.BuyLots(it, max * 3)
    T.eq(#NW.Calls("BuyMerchantItem"), 4, "the first lot at once")
    -- It sells out: the next item slides up into slot 1.
    table.remove(NW.state.merchant.items, 1)
    stub.RunTimers()
    T.eq(#NW.Calls("BuyMerchantItem"), 4, "nothing else bought")
end)

T.test("npc shop: a click buys one; too dear or not for you shows soft red", function()
    local N = load()
    NW.Merchant()
    frame()
    local tiles = {}
    for _, p in ipairs(shop(N).pieces) do if p.spec then tiles[#tiles + 1] = p end end
    tiles[1]:Click("LeftButton")
    T.deq(NW.Calls("BuyMerchantItem"), { { 1 } })
    tiles[3]:Click("LeftButton")
    T.eq(#NW.Calls("BuyMerchantItem"), 1, "the backpack is too dear: nothing bought")
    local r, g = unpack(tiles[3].sub.__textColor)
    T.truthy(r > g, "its price in soft red")
    local ir, ig = tiles[4].icon:GetVertexColor()
    T.truthy(ir > 0.85 and ig < 0.25, "not for you: a red that shows on the art")
    local nr, ng = unpack(tiles[4].name.__textColor)
    T.truthy(nr > ng + 0.4, "and its name soft red")
end)

T.test("npc shop: an item paid in items shows what it costs, not \"Special cost\"", function()
    local N = load()
    NW.Merchant({ items = {
        { name = "Pattern: Pearly Boots", price = 0, extended = true,
          costs = { { texture = 132889, value = 3, link = "|Hitem:2589|h[Linen Cloth]|h" } } },
        { name = "Marked Gear", price = 500, extended = true, costs = { { texture = 1, value = 2, currency = "Marks" } } },
    } })
    frame()
    local tiles = {}
    for _, p in ipairs(shop(N).pieces) do if p.spec then tiles[#tiles + 1] = p end end
    local a, b = tiles[1].sub:GetText(), tiles[2].sub:GetText()
    T.truthy(a:find("^3 |T132889:"), "its count and icon: " .. a)
    T.truthy(b:find("2 |T1:", 1, true) and b:find("silver"), "money and the token both: " .. b)
end)

T.test("npc shop: the header shows what you hold of the shelf's costs", function()
    local N = load()
    local count = C_Item.GetItemCount
    C_Item.GetItemCount = function() return 7 end
    NW.Merchant({ items = {
        { name = "Pattern: Pearly Boots", price = 0, extended = true,
          costs = { { texture = 132889, value = 3, link = "|Hitem:2589|h[Linen Cloth]|h" } } },
    } })
    frame()
    C_Item.GetItemCount = count
    local w = N.frame.wallet
    T.truthy(w:IsShown(), "shown with the shop")
    T.truthy(w:GetText():find("^7 |T132889:"), "what your bags hold: " .. w:GetText())
end)

-- The game's MerchantFrame_OnUpdate sets these; parked, it never runs.
T.test("npc shop: hovering a tile shows the game's buy cursor, red when too dear", function()
    local N = load()
    NW.Merchant({ buyback = { { name = "Linen Cloth", price = 5 } } })
    frame()
    local tiles = {}
    for _, p in ipairs(shop(N).pieces) do if p.spec then tiles[#tiles + 1] = p end end
    tiles[1]:GetScript("OnEnter")(tiles[1])
    tiles[1]:GetScript("OnLeave")(tiles[1])
    tiles[3]:GetScript("OnEnter")(tiles[3])
    T.deq(NW.Calls("SetCursor"), { { "BUY_CURSOR" }, { "BUY_ERROR_CURSOR" } })
    T.eq(#NW.Calls("ResetCursor"), 1, "put back on leave")
    shop(N).tabBack:Click()
    frame()
    for _, p in ipairs(shop(N).pieces) do
        if p.spec and p:IsShown() then p:GetScript("OnEnter")(p); break end
    end
    T.deq(NW.Calls("ShowBuybackSellCursor"), { { 1 } }, "the buy-back one on that tab")
end)

-- Like the game's shop, Shift-click opens a quantity box: one lot to start,
-- steps of a lot, capped at the max stack and what you can afford.
T.test("npc shop: Shift-click asks how many, never buys on its own", function()
    local N, ns = load()
    NW.state.money = 100   -- 4 lots of water at 25
    NW.Merchant()
    frame()
    local tiles = {}
    for _, p in ipairs(shop(N).pieces) do if p.spec then tiles[#tiles + 1] = p end end
    _G.IsShiftKeyDown = function() return true end
    tiles[1]:Click("LeftButton")
    _G.IsShiftKeyDown = function() return false end
    T.eq(#NW.Calls("BuyMerchantItem"), 0, "nothing bought yet")
    local box = ns.Shop.box
    T.eq(box:IsShown(), true, "the amount box")
    T.eq(box.num:GetText(), "5", "one lot to start")
    T.eq(box.buy.text:GetText(), "Buy · " .. DaylightUI.MoneyString(25))
    box.more:Click(); box.more:Click()
    T.eq(box.num:GetText(), "15", "steps of a lot")
    box.more:Click(); box.more:Click(); box.more:Click()
    T.eq(box.num:GetText(), "20", "no more than you can pay for")
    box.less:Click()
    box.buy:Click()
    T.deq(NW.Calls("BuyMerchantItem"), { { 1, 15 } })
    T.eq(box:IsShown(), false, "closed after buying")

    -- Typed: whole lots only; Escape closes it before the shop.
    _G.IsShiftKeyDown = function() return true end
    tiles[1]:Click("LeftButton")
    _G.IsShiftKeyDown = function() return false end
    box.num:SetText("12")
    box.num:GetScript("OnTextChanged")(box.num, true)
    T.eq(box.buy.text:GetText(), "Buy · " .. DaylightUI.MoneyString(50), "12 -> two lots")
    T.eq(N.OnKey("ESCAPE"), true)
    T.eq(box:IsShown(), false)
    T.eq(#NW.Calls("CloseMerchant"), 0, "the shop stays open")
    T.eq(#NW.Calls("BuyMerchantItem"), 1)

    -- Something that comes one at a time: Shift-click is a plain buy.
    NW.state.money = 99999
    _G.IsShiftKeyDown = function() return true end
    local items = NW.Goods()
    items[3].maxStack = 1
    NW.Merchant({ items = items })
    frame()
    tiles = {}
    for _, p in ipairs(shop(N).pieces) do if p.spec then tiles[#tiles + 1] = p end end
    tiles[3]:Click("LeftButton")
    _G.IsShiftKeyDown = function() return false end
    T.eq(box:IsShown(), false)
    T.deq(NW.Calls("BuyMerchantItem")[2], { 3 })
end)

-- One purchase can't take more than a stack, so more than that is bought a stack
-- at a time, a moment apart.
T.test("npc shop: the amount box buys several stacks one after another", function()
    local N, ns = load()
    NW.state.money = 2000   -- 80 lots of water at 25: plenty
    NW.Merchant()
    frame()
    local tiles = {}
    for _, p in ipairs(shop(N).pieces) do if p.spec then tiles[#tiles + 1] = p end end
    _G.IsShiftKeyDown = function() return true end
    tiles[1]:Click("LeftButton")
    _G.IsShiftKeyDown = function() return false end
    local box = ns.Shop.box
    box.num:SetText("50")
    box.num:GetScript("OnTextChanged")(box.num, true)
    T.eq(box.buy.text:GetText(), "Buy · " .. DaylightUI.MoneyString(250), "50 = ten lots")
    box.buy:Click()
    T.deq(NW.Calls("BuyMerchantItem"), { { 1, 20 } }, "the first stack at once")
    stub.RunTimers()
    T.deq(NW.Calls("BuyMerchantItem"), { { 1, 20 }, { 1, 20 }, { 1, 10 } }, "then the rest")
end)

T.test("npc shop: something very dear asks a second click", function()
    local N = load()
    NW.state.money = 99999999
    NW.Merchant()
    frame()
    local lotus
    for _, p in ipairs(shop(N).pieces) do if p.name and p.name:GetText() == "Black Lotus" then lotus = p end end
    lotus:Click("LeftButton")
    T.eq(#NW.Calls("BuyMerchantItem"), 0)
    T.eq(lotus.sub:GetText(), "Click again to buy")
    lotus:Click("LeftButton")
    T.eq(#NW.Calls("BuyMerchantItem"), 1)
end)

-- Every money, bag and item-info event refills the shelf. It reads the shelf
-- once, and only rescans bags for junk after they changed.
T.test("npc shop: a refill reads the shelf once and the bags only after BAG_UPDATE_DELAYED", function()
    local N = load()
    local walks, old, oldItem = 0, _G.C_Container, _G.C_Item
    -- a gray item that sells for 25 copper
    _G.C_Item = setmetatable({ GetItemInfo = function() return "Broken Fang", nil, 0, 1, 1, "", "", 20, "", 134400, 25 end },
        { __index = oldItem })
    _G.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
        GetContainerItemInfo = function(bag, slot)
            if slot == 1 then walks = walks + 1 end
            return { quality = 0, itemID = 7073, stackCount = 1 }
        end,
    }
    NW.Merchant({})
    frame()
    local reads, info = 0, C_MerchantFrame.GetItemInfo
    C_MerchantFrame.GetItemInfo = function(i) if i == 1 then reads = reads + 1 end; return info(i) end
    local w0 = walks
    stub.FireEvent("PLAYER_MONEY")
    stub.FireEvent("GET_ITEM_INFO_RECEIVED", 1, true)
    frame()
    T.eq(reads, 1, "the shelf read once for the tiles and the wallet")
    T.eq(walks, w0, "the bags didn't change: no walk")
    stub.FireEvent("BAG_UPDATE_DELAYED")
    frame()
    T.eq(walks, w0 + 1, "the bags changed: read again")
    _G.C_Container, _G.C_Item = old, oldItem
end)

T.test("npc shop: Sell junk and Repair through the game; off when there's nothing", function()
    local N = load()
    NW.Merchant({ junk = 0, repair = 0 })
    frame()
    local foot = shop(N).foot
    T.eq(foot.buttons[1].spec.off, true, "no junk")
    T.eq(foot.buttons[2].spec.off, true, "nothing to repair")
    NW.Merchant({ junk = 3, repair = 160 })
    frame()
    local kits, wasKit, wasPlay = {}, _G.SOUNDKIT, _G.PlaySound
    _G.SOUNDKIT, _G.PlaySound = { ITEM_REPAIR = 7994 }, function(kit) kits[#kits + 1] = kit end
    foot:Press(2)
    _G.SOUNDKIT, _G.PlaySound = wasKit, wasPlay
    T.eq(#NW.Calls("RepairAllItems"), 1)
    T.deq(kits, { 7994 }, "the game's repair sound: its button never runs behind ours")
end)

T.test("npc shop: the search folds the shelf; Buy back lists what you sold", function()
    local N = load()
    NW.Merchant({ buyback = { { name = "Broken Fang", price = 12, count = 3 } } })
    frame()
    shop(N).search:SetText("jerky")
    shop(N).search:GetScript("OnTextChanged")(shop(N).search)
    T.deq(tileNames(N), { "Tough Jerky" })
    shop(N).tabBack:Click()
    T.deq(tileNames(N), { "Broken Fang" })
    for _, p in ipairs(shop(N).pieces) do if p.spec then p:Click("LeftButton") end end
    T.deq(NW.Calls("BuybackItem"), { { 1 } })
end)

-- The strip over the footer shows the newest sale, like the game's buyback slot
-- (GetBuybackItemInfo(GetNumBuybackItems())).
local function lastLine(N)
    for _, b in ipairs(shop(N).last.stack.used) do
        if b:IsShown() and b.lineSpec then return b end
    end
end

T.test("npc shop: the last sold item waits over the footer, either click buys it back", function()
    local N = load()
    NW.Merchant({ buyback = { { name = "Broken Fang", price = 12, count = 3 }, { name = "Linen Cloth", price = 5 } } })
    frame(3)
    T.truthy(shop(N).last:IsShown(), "something is sold")
    local line = lastLine(N)
    T.eq(line.lineSpec.text, "Linen Cloth", "the newest, not the first")
    T.eq(line.lineSpec.sub, "Last sold")
    line:Click("LeftButton")
    line:Click("RightButton")
    T.deq(NW.Calls("BuybackItem"), { { 2 }, { 2 } })
    line:GetScript("OnEnter")(line)
    line:GetScript("OnLeave")(line)
    T.deq(NW.Calls("ShowBuybackSellCursor"), { { 2 } }, "the buy-back cursor")
    T.eq(#NW.Calls("ResetCursor"), 1, "put back on leave")
end)

T.test("npc shop: the last sold strip is the Shop tab's, and only with something sold", function()
    local N = load()
    NW.Merchant()
    frame(3)
    T.falsy(shop(N).last:IsShown(), "nothing sold: the shelf keeps its room")
    NW.Merchant({ buyback = { { name = "Linen Cloth", price = 5 } } })
    frame(3)
    T.truthy(shop(N).last:IsShown())
    shop(N).tabBack:Click()
    frame(30)
    T.falsy(shop(N).last:IsShown(), "Buy back lists them all already")
end)

T.test("npc shop: the sample's Sell junk fills the strip, its buy back empties it", function()
    local N = load()
    N.Sample()
    frame(3)
    DaylightUI.Npc.Shop.StartSample()
    N.state.sample = true
    DaylightUI.Npc.Shop.state.tab = "shop"
    T.eq(#DaylightUI.Npc.Shop.Sold(), 0)
    DaylightUI.Npc.Shop.SellJunk()
    T.eq(#DaylightUI.Npc.Shop.Sold(), 1)
    DaylightUI.Npc.Shop.Buy(DaylightUI.Npc.Shop.SAMPLE_SOLD)
    T.eq(#DaylightUI.Npc.Shop.Sold(), 0)
end)

T.test("npc shop: Escape leaves the shop; the number keys never buy", function()
    local N = load()
    NW.Merchant()
    frame()
    T.eq(N.OnKey("1"), false, "your bar's 1, not a purchase")
    T.eq(#NW.Calls("BuyMerchantItem"), 0)
    T.eq(N.OnKey("ESCAPE"), true)
    T.eq(#NW.Calls("CloseMerchant"), 1)
    frame(); settle()
    T.eq(N.frame:IsShown(), false)
    T.deq(NW.Calls("CloseAllBags"), { { "MerchantFrame" } })
end)

T.test("npc shop: walking away: the game hides its window, we tell the server", function()
    local N = load()
    NW.Merchant()
    frame()
    HideUIPanel(MerchantFrame)
    frame()
    T.eq(#NW.Calls("CloseMerchant"), 1)
    settle()
    T.eq(N.frame:IsShown(), false)
end)

-- Other addons work with the game's vendor window: they hook it, or move it
-- off screen and open their own (TradeSkillMaster sends it to 100000, 100000).
-- So it's kept really open while this window steps aside.

T.test("npc shop: the game's vendor really opens, so an addon hooking its OnShow hears it", function()
    load()
    local heard = 0
    MerchantFrame:HookScript("OnShow", function() heard = heard + 1 end)
    T.eq(MerchantFrame:GetParent(), DaylightUI.Win.Followers.aside)
    NW.Merchant()
    frame()
    T.eq(heard, 1)
    T.eq(#NW.Calls("OpenAllBags"), 1, "once: the game's own, not ours too")
    T.eq(#NW.Calls("ResetSetMerchantFilter"), 1)
end)

local function sendAway()
    MerchantFrame:ClearAllPoints()
    MerchantFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100000, 100000)
end

T.test("npc shop: an addon sending the game's vendor off screen gets the shop to itself", function()
    local N = load()
    NW.Merchant()
    frame()
    T.eq(N.frame:IsShown(), true)
    sendAway()
    frame()
    settle()
    T.eq(N.frame:IsShown(), false, "ours stepped aside")
    T.eq(N.state.mode, nil)
    T.eq(#NW.Calls("CloseMerchant"), 0, "the shop stays open for the other addon")
    T.eq(MerchantFrame:IsShown(), true)
end)

T.test("npc shop: an addon that took the vendor as it opened: ours never shows", function()
    local N = load()
    NW.Merchant()
    sendAway()
    frame()
    T.eq(N.frame:IsShown(), false)
    T.eq(N.state.mode, nil)
end)

T.test("npc shop: the addon puts the game's vendor back: ours opens on it", function()
    local N = load()
    NW.Merchant()
    frame()
    sendAway()
    frame()
    settle()
    MerchantFrame:ClearAllPoints()
    MerchantFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    frame()
    frame()
    T.eq(N.state.mode, "merchant")
    T.eq(N.frame:IsShown(), true)
end)

T.test("npc shop: shrinking the game's vendor to nothing counts as taking it", function()
    local N = load()
    NW.Merchant()
    frame()
    MerchantFrame:SetScale(0.001)
    frame()
    settle()
    T.eq(N.frame:IsShown(), false)
    T.eq(#NW.Calls("CloseMerchant"), 0)
end)

T.test("npc shop: an addon parking the game's vendor under its own frame gets it too", function()
    local N = load()
    local theirs = CreateFrame("Frame", nil, UIParent)
    NW.Merchant()
    frame()
    MerchantFrame:SetParent(theirs)
    frame()
    settle()
    T.eq(N.frame:IsShown(), false)
    T.eq(#NW.Calls("CloseMerchant"), 0)
end)

T.test("npc shop: the shop closing under the other addon leaves ours shut", function()
    local N = load()
    NW.Merchant()
    frame()
    sendAway()
    frame()
    settle()
    CloseMerchant()
    frame(2)
    settle()
    T.eq(N.frame:IsShown(), false)
    T.eq(MerchantFrame:IsShown(), false)
end)

T.test("npc shop: the sample talk's goods open the sample shelf and buy nothing for real", function()
    local N = load()
    N.Sample()
    settle()
    N.rows[3]:Click()
    settle()
    T.eq(N.state.mode, "merchant")
    T.eq(N.frame:GetWidth(), 520)
    for _, p in ipairs(shop(N).pieces) do if p.spec then p:Click("LeftButton"); break end end
    T.eq(#NW.state.calls, 0)
end)

T.test("npc shop: vendors switched off: the game's vendor stays the game's", function()
    stub.Load({ before = function()
        NW.world()()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { NPC = { vendor = false } } } } }
    end })
    T.eq(MerchantFrame:GetParent(), UIParent)
    T.eq(GossipFrame:GetParent(), DaylightUI.Win.Followers.hidden, "the talk is still ours")
end)

-- Text colors: money gold, the picked shop tab in the accent, a quest in
-- progress amber, trivial ones dimmed.
T.test("npc: text color: busy quest amber, trivial off, shop money gold, picked tab pops", function()
    local N, ns = load()
    local INK = DaylightUI.Style.INK
    local function warm(c) return math.max(c[1], c[2], c[3]) - math.min(c[1], c[2], c[3]) > 0.04 end
    T.truthy(warm(N.BUSY) and N.BUSY[1] > N.BUSY[3], "busy is amber")
    T.rgb(ns.Data.QuestColor(1, 1, true), INK.OFF, "trivial")
    NW.Merchant({ junk = 2, repair = 160 })
    frame(); settle()
    T.rgb({ N.frame.money:GetTextColor() }, INK.MONEY, "header money")
    T.rgb({ shop(N).tabShop.text:GetTextColor() }, { DaylightUI.Style.Pop() }, "picked tab")
    T.rgb({ shop(N).tabBack.text:GetTextColor() }, INK.LABEL, "tab not picked")
end)

T.test("npc: the corner grip sizes each page on its own, stays on the game's spot, a right-click puts it back", function()
    local N, ns = load()
    NW.Merchant({ junk = 2 })
    frame()
    local f = N.frame
    T.eq(f.current, "shop")
    local grip = f.grip
    T.truthy(grip, "the window has a grip")
    -- The fake game has no layout: a fixed top-left for the drag's sums.
    f.GetLeft = function() return 100 end
    f.GetTop = function() return 700 end
    local e = f:GetEffectiveScale()
    stub.cursorPos = { 600 * e, 200 * e }
    grip:GetScript("OnMouseDown")(grip, "LeftButton")
    stub.cursorPos = { 680 * e, 140 * e }
    stub.RunOnUpdate(grip, 1 / 30)
    grip:GetScript("OnMouseUp")(grip, "LeftButton")
    T.eq(f:GetWidth(), 600)
    T.eq(f:GetHeight(), 600)
    T.deq(ns.module.db.sizes, { shop = { 600, 600 } }, "the shop's size only")
    local _, rel, _, x, y = f:GetPoint(1)
    T.eq(rel, UIParent, "on the game's spot again")
    T.eq(x, 16 / f:GetScale()); T.eq(y, -116 / f:GetScale())
    -- Right-click: the made size back.
    grip:GetScript("OnMouseUp")(grip, "RightButton")
    settle()
    T.eq(ns.module.db.sizes, nil)
    T.near(f:GetWidth(), 520, 0.5)
end)

-- ---------------------------------------------------------------------
-- The immersive look (Npc/Scene.lua)
-- ---------------------------------------------------------------------

T.test("npc immersive: a talk opens the card on the right, the whole UI faded, the window stays shut", function()
    local N, ns = load()
    ns.module.db.look = "immersive"
    NW.Gossip(GOSSIP)
    frame(); settle()
    T.eq(DaylightUI.Win.IsOpen(N.scene), true)
    T.eq(N.frame:IsShown(), false)
    T.eq(N.scene.title:GetText(), "William Pestle")
    T.deq(texts(N), { "Kobold Candles  " .. DaylightUI.Win.Parts.Hex(ns.Data.QuestColor(60, 6)) .. "6|r",
        "Make this inn your home.", "Let me browse your goods." })
    local p = { N.scene:GetPoint(1) }
    T.eq(p[1], "RIGHT")
    T.eq(UIParent:GetAlpha(), 0, "the whole UI fades away")
    T.eq(N.scene:IsIgnoringParentAlpha(), true, "the card stays")
    N.Goodbye()
    settle()
    T.eq(N.scene:IsShown(), false)
    T.eq(UIParent:GetAlpha(), 1, "the UI comes back")
    T.eq(#NW.Calls("CloseGossip"), 1)
end)

T.test("npc immersive: the words are written out; the first Space shows them all, the next one answers", function()
    local N, ns = load()
    ns.module.db.look = "immersive"
    ns.module.db.typeText = true
    local kits, wasKit, wasPlay = {}, _G.SOUNDKIT, _G.PlaySound
    _G.SOUNDKIT, _G.PlaySound = { IG_WRITE_QUEST = 3093 }, function(kit) kits[#kits + 1] = kit end
    NW.Quest("DETAIL", NW.Candles())
    frame()
    T.eq(ns.Scene.Typing(), true)
    stub.RunOnUpdate(ns.Scene.frame.typer, 1 / 30)
    _G.SOUNDKIT, _G.PlaySound = wasKit, wasPlay
    T.deq(kits, { 3093 }, "the game's quill while the words are written")
    T.eq(N.OnKey("SPACE"), true)
    T.eq(ns.Scene.Typing(), false, "all at once")
    T.eq(ns.Scene.frame.typer:IsShown(), false, "the quill stops with the words")
    T.eq(#NW.Calls("AcceptQuest"), 0, "never accepted on the same press")
    T.eq(N.OnKey("SPACE"), true)
    T.eq(#NW.Calls("AcceptQuest"), 1)
end)

T.test("npc immersive: Text Slow Mode off (the default), the words are all there at once", function()
    local N, ns = load()
    ns.module.db.look = "immersive"
    NW.Gossip(GOSSIP)
    frame()
    T.eq(ns.Scene.Typing(), false)
end)

T.test("npc immersive: a vendor from the talk opens the window and lets the UI back", function()
    local N, ns = load({ vendor = true })
    ns.module.db.look = "immersive"
    NW.Gossip(GOSSIP)
    frame(); settle()
    N.rows[3]:Click()
    NW.CloseGossip(true)
    NW.Merchant({ items = NW.Goods() })
    frame(); settle()
    T.eq(N.state.mode, "merchant")
    T.eq(DaylightUI.Win.IsOpen(N.frame), true)
    T.eq(DaylightUI.Win.IsOpen(N.scene), false)
    T.eq(UIParent:GetAlpha(), 1)
end)

T.test("npc immersive: Fade the UI off leaves everything shown", function()
    local N, ns = load()
    ns.module.db.look = "immersive"
    ns.module.db.fadeUI = false
    NW.Gossip(GOSSIP)
    frame(); settle()
    T.eq(DaylightUI.Win.IsOpen(N.scene), true)
    T.eq(UIParent:GetAlpha(), 1)
end)

-- The game's camera settings and its warning.
local function camera(start)
    local cv = {}
    for k, v in pairs(start or {}) do cv[k] = v end
    _G.GetCVar = function(k) return cv[k] end
    _G.SetCVar = function(k, v) cv[k] = v end
    _G.C_CVar = { GetCVar = _G.GetCVar, SetCVar = _G.SetCVar }
    local handlers = {}
    _G.GameEvent = {
        HandleExperimentalCVarConfirmationNeeded = function() end,
        RegisterInternalEvent = function(e, h) handlers[e] = h end,
        UnregisterInternalEvent = function(e) handlers[e] = nil; handlers.quieted = (handlers.quieted or 0) + 1 end,
    }
    handlers.EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED = _G.GameEvent.HandleExperimentalCVarConfirmationNeeded
    return cv, handlers
end

T.test("npc immersive: the camera comes in over your shoulder, the warning quiet, and everything goes back after", function()
    local N, ns = load()
    local cv, handlers = camera({ test_cameraOverShoulder = "0", CameraKeepCharacterCentered = "1",
        test_cameraTargetFocusInteractEnable = "0", test_cameraTargetFocusInteractStrengthPitch = "0" })
    ns.module.db.look = "immersive"
    NW.Gossip(GOSSIP)
    frame(); settle()
    T.eq(tonumber(cv.test_cameraOverShoulder), ns.Scene.SHOULDER)
    T.eq(tonumber(cv.test_cameraTargetFocusInteractEnable), 1, "looks at the NPC")
    T.eq(tonumber(cv.CameraKeepCharacterCentered), 0)
    T.truthy(handlers.quieted, "no warning for Daylight UI's own change")
    T.truthy(DaylightUIDB.npcCamera, "your settings kept per account")
    N.Goodbye()
    settle()
    T.eq(cv.test_cameraOverShoulder, "0")
    T.eq(cv.CameraKeepCharacterCentered, "1")
    T.eq(cv.test_cameraTargetFocusInteractEnable, "0")
    T.eq(DaylightUIDB.npcCamera, nil)
    stub.RunTimers()
    -- Registering the game's handler from addon code would leave it tainted, and the
    -- warning would then open the game's pop-up under that taint.
    T.isnil(handlers.EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED, "the game's warning never registered back from addon code")
    local quieted = handlers.quieted
    NW.Gossip(GOSSIP)
    frame(); settle()
    N.Goodbye(); settle()
    stub.RunTimers()
    T.eq(handlers.quieted, quieted, "silenced once, not around every change")
end)

T.test("npc: the plain window look leaves the game's camera calls alone", function()
    -- Other modules (the personal resource display) hook these too, so count only
    -- the NPC window's own hooks.
    local hooked = {}
    local realHook = _G.hooksecurefunc
    _G.hooksecurefunc = function(a, b, c)
        local src = debug.getinfo(2, "S").source or ""
        if type(a) == "string" and src:find("Npc.Scene%.lua") then hooked[a] = true end
        return realHook(a, b, c)
    end
    local ok, err = pcall(function()
        local N = load()
        local _, handlers = camera({})
        NW.Gossip(GOSSIP)
        frame(); settle()
        N.Goodbye(); settle()
        stub.FireEvent("PLAYER_REGEN_DISABLED")
        T.isnil(next(hooked), "no camera call hooked")
        T.isnil(handlers.quieted, "the game's warning untouched")
    end)
    _G.hooksecurefunc = realHook
    if not ok then error(err, 0) end
end)

T.test("npc immersive: a fight or a logout mid-talk puts your camera back at once", function()
    local N, ns = load()
    local cv = camera({ test_cameraOverShoulder = "0", CameraKeepCharacterCentered = "1" })
    ns.module.db.look = "immersive"
    NW.Gossip(GOSSIP)
    frame(); settle()
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.eq(cv.test_cameraOverShoulder, "0")
    T.eq(cv.CameraKeepCharacterCentered, "1")
    N.Goodbye(); settle()
    NW.Gossip(GOSSIP)
    frame(); settle()
    stub.FireEvent("PLAYER_LOGOUT")
    T.eq(cv.CameraKeepCharacterCentered, "1")
end)

-- CameraZoomIn/Out set where the camera is heading and it eases there.
-- GetCameraZoom says where it is now; tests move stub.cameraZoom.
local function zoomCamera(start)
    local cam = { heading = start, calls = 0 }
    stub.cameraZoom = start
    _G.CameraZoomIn = function(d) cam.heading = cam.heading - d; cam.calls = cam.calls + 1 end
    _G.CameraZoomOut = function(d) cam.heading = cam.heading + d; cam.calls = cam.calls + 1 end
    function cam.Arrive() stub.cameraZoom = cam.heading end
    function cam.Done()
        stub.cameraZoom = nil
        _G.CameraZoomIn, _G.CameraZoomOut = function() end, function() end
    end
    return cam
end

T.test("npc immersive: the zoom goes back to yours, even from a talk that ended before the camera got there", function()
    local N, ns = load()
    camera({})
    local cam = zoomCamera(25)
    ns.module.db.look = "immersive"
    NW.Gossip(GOSSIP)
    frame(); settle()
    T.eq(cam.heading, ns.Scene.ZOOM, "comes in")
    cam.Arrive()
    N.Goodbye(); settle()
    T.eq(cam.heading, 25, "a whole talk: back to yours")
    cam.Arrive()
    NW.Gossip(GOSSIP)
    frame(); settle()
    stub.cameraZoom = 16   -- a quick answer: still on its way in
    N.Goodbye(); settle()
    T.eq(cam.heading, 25, "a quick talk: back to yours too")
    cam.Done()
end)

T.test("npc immersive: a talk opening while the camera is on its way back still knows your zoom", function()
    local N, ns = load()
    camera({})
    local cam = zoomCamera(25)
    ns.module.db.look = "immersive"
    NW.Gossip(GOSSIP)
    frame(); settle()
    cam.Arrive()
    N.Goodbye(); settle()
    stub.cameraZoom = 9    -- on its way back out
    NW.Gossip(GOSSIP)
    frame(); settle()
    T.eq(cam.heading, ns.Scene.ZOOM, "comes in to the same spot")
    N.Goodbye(); settle()
    T.eq(cam.heading, 25, "and all the way back to yours")
    cam.Done()
end)

T.test("npc immersive: a long time after a talk, your camera is read fresh", function()
    local N, ns = load()
    camera({})
    local cam = zoomCamera(25)
    local realTime, now = _G.GetTime, 100
    _G.GetTime = function() return now end
    ns.module.db.look = "immersive"
    NW.Gossip(GOSSIP)
    frame(); settle()
    cam.Arrive()
    N.Goodbye(); settle()
    cam.Arrive()
    now = now + 60
    cam.heading, stub.cameraZoom = 12, 12   -- the game moved it some way no call shows
    NW.Gossip(GOSSIP)
    frame(); settle()
    T.eq(cam.heading, ns.Scene.ZOOM)
    N.Goodbye(); settle()
    T.eq(cam.heading, 12)
    _G.GetTime = realTime
    cam.Done()
end)

T.test("npc immersive: zooming yourself mid-talk keeps your zoom", function()
    local N, ns = load()
    camera({})
    local cam = zoomCamera(25)
    ns.module.db.look = "immersive"
    NW.Gossip(GOSSIP)
    frame(); settle()
    cam.Arrive()
    MoveViewOutStart(1)
    stub.cameraZoom = 7
    cam.heading = 7
    N.Goodbye(); settle()
    T.eq(cam.heading, 7, "yours now: it stays")
    cam.Done()
end)

T.test("npc immersive: a fight or a logout mid-talk gives your zoom back too", function()
    local N, ns = load()
    camera({})
    local cam = zoomCamera(25)
    ns.module.db.look = "immersive"
    NW.Gossip(GOSSIP)
    frame(); settle()
    cam.Arrive()
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.eq(cam.heading, 25, "a fight")
    N.Goodbye(); settle()
    T.eq(cam.heading, 25, "only once")
    cam.Arrive()
    NW.Gossip(GOSSIP)
    frame(); settle()
    T.eq(cam.heading, ns.Scene.ZOOM)
    cam.Arrive()
    stub.FireEvent("PLAYER_LOGOUT")
    T.eq(cam.heading, 25, "a /reload")
    cam.Done()
end)

T.test("npc immersive: camera off or mounted: your camera is never touched", function()
    local N, ns = load()
    local cv = camera({ test_cameraOverShoulder = "0" })
    ns.module.db.look = "immersive"
    stub.mounted = true
    NW.Gossip(GOSSIP)
    frame(); settle()
    T.eq(cv.test_cameraOverShoulder, "0")
    stub.mounted = false
end)

T.test("npc: a press on a row of the page before never reaches the game (a quest's reward page opening)", function()
    local N = load()
    NW.Gossip({ active = { { title = "The Balance of Nature", questID = 456, isComplete = true } } })
    frame()
    local press = N.rows[1].spec.onClick
    NW.Quest("COMPLETE", NW.Candles())
    frame()
    T.noerror(function() press(N.rows[1]) end)
end)

T.test("npc: with the controller UI on, buttons name no keyboard keys and a controller starts on the main button", function()
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    _G.GamepadMode = { FrameControlsManager = { FrameShown = function() end, FrameHidden = function() end } }
    local N = load()
    local aimed
    _G.SmartNavigation = { RefreshButtonGroups = function() end, GetCurrentButton = function() end,
        SetTargetButtonForFrame = function(_, _, b) aimed = b end }
    DaylightUI.Pad.focused = N.frame
    NW.Quest("DETAIL", NW.Candles())
    settle()
    local main = N.frame.pages.talk.foot.buttons[1]
    T.eq(N.Buttons()[1].key, nil)
    T.eq(aimed, main)
    DaylightUI.Pad.focused = nil
    _G.InputUtil, _G.GamepadMode, _G.SmartNavigation = nil, nil, nil
end)

local function shopTile(f, name)
    local function walk(fr)
        for _, c in ipairs({ fr:GetChildren() }) do
            if type(c.spec) == "table" and c.spec.shopItem and c.spec.shopItem.name == name and c:IsVisible() then return c end
            local hit = walk(c)
            if hit then return hit end
        end
    end
    return walk(f)
end

T.test("npc shop on a controller: A buys, X buys a stack, as the game's vendor", function()
    local N = load()
    NW.Merchant()
    frame()
    settle()
    T.eq(N.state.mode, "merchant")
    local water = shopTile(N.frame, "Refreshing Spring Water")
    T.truthy(water, "the water's tile")
    T.eq(N.PadSelect(water), CONTEXT_ACTION_LABEL_BUY or "Buy")
    local x
    for _, e in ipairs(N.frame.padKeys) do
        if e.key == "X" and e.when(water) then x = x or e end
    end
    T.truthy(x, "X has something to do on a stack")
    T.eq(x.label, CONTEXT_ACTION_LABEL_MULTI_BUY or "Buy a stack")
    for _, e in ipairs(N.frame.padKeys) do
        if e.key == "Y" then T.falsy(e.when(), "the spellbook is the trainer's") end
    end
end)

-- Seen in game: a supply box hand-in gave 15 silver and 30 Trade Commitment, and the
-- window showed only the silver. The game lists currencies apart from item rewards.
T.test("npc: a quest's currency rewards show beside its items, on the offer and the hand-in", function()
    local N = load()
    local function names()
        local out = {}
        for _, p in ipairs(N.frame.pages[N.frame.current].pieces or {}) do
            if p.name and p.spec then out[#out + 1] = p.name:GetText() end
        end
        return out
    end
    local q = NW.Candles({ choices = {}, rewards = { { name = "Linen Cloth", itemID = 2589 } },
        currencies = { { name = "Trade Commitment", count = 30, currencyID = 3200 } } })
    NW.Quest("DETAIL", q)
    frame()
    T.deq(names(), { "Linen Cloth", "Trade Commitment" }, "the offer")
    NW.Quest("COMPLETE", q)
    frame()
    T.deq(names(), { "Linen Cloth", "Trade Commitment" }, "the hand-in")
    local tile
    for _, p in ipairs(N.frame.pages[N.frame.current].pieces) do
        if p.spec and p.name:GetText() == "Trade Commitment" then tile = p end
    end
    T.eq(tile.count:GetText(), "30")
    local before = #N.frame.pages[N.frame.current].pieces
    for _ = 1, 20 do frame() end
    T.eq(#N.frame.pages[N.frame.current].pieces, before, "the watch doesn't see it as a change and refill forever")
end)

T.test("npc shop: a limited item says how many the vendor has left, and you can't ask for more", function()
    local N = load()
    NW.Merchant({ items = { { name = "Raw Brilliant Smallfish", price = 18, available = 5 }, { name = "Tough Jerky", price = 25, stack = 5 } } })
    frame(); settle()
    local fish = shopTile(N.frame, "Raw Brilliant Smallfish")
    local jerky = shopTile(N.frame, "Tough Jerky")
    local plain = fish.sub:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    T.truthy(plain:find("5 left", 1, true), "its stock after the price")
    T.falsy(jerky.sub:GetText():find("left", 1, true), "an unlimited one says nothing")
    local _, afford = stub.npc.Shop.MaxOf(fish.spec.shopItem)
    T.truthy(afford <= 5, "the amount box stops at the stock")
end)

T.test("npc: with Immersion talking to NPCs, gossip and quests are left to it; the vendor still opens Daylight UI's", function()
    local N = load({ before = function() stub.loadedAddOns.Immersion = true end })
    T.eq(DaylightUI.npcTalkAddon, "Immersion")
    T.truthy(GossipFrame:GetParent() ~= DaylightUI.Win.Followers.hidden, "the gossip window isn't parked by Daylight UI")
    T.truthy(QuestFrame:GetParent() ~= DaylightUI.Win.Followers.hidden, "nor the quest window")
    NW.Gossip(GOSSIP)
    frame(); settle()
    T.falsy(N.frame:IsShown(), "no second talk window over Immersion's")
    NW.Quest("DETAIL", NW.Candles())
    frame(); settle()
    T.falsy(N.frame:IsShown(), "nor on a quest page")
    T.falsy(N.scene:IsShown(), "nor the immersive card")
    NW.Merchant()
    frame(); settle()
    T.truthy(DaylightUI.Win.IsOpen(N.frame), "a vendor still opens Daylight UI's window")
    T.eq(N.state.mode, "merchant")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)


-- The game's own vendor (Mainline/MerchantFrame.lua), behavior by behavior.

local function tilesOf(N)
    local out = {}
    for _, p in ipairs(shop(N).pieces) do if p.spec and p.spec.shopItem then out[#out + 1] = p end end
    return out
end

-- The game's tooltip (the NPC world has none of its own).
local function gameTip()
    if not _G.GameTooltip then
        local tip = stub.CompareTooltip("GameTooltip")
        function tip:SetOwner(o) self.__owner = o end
        function tip:GetOwner() return self.__owner end
        function tip:IsOwned(o) return self.__owner == o end
        _G.GameTooltip = tip
    end
    return _G.GameTooltip
end

-- What a hover writes on GameTooltip, as one string.
local function hoverText(b)
    gameTip()
    local lines, was = {}, { GameTooltip.AddLine, GameTooltip.AddDoubleLine }
    GameTooltip.AddLine = function(_, t) lines[#lines + 1] = tostring(t) end
    GameTooltip.AddDoubleLine = function(_, a, c) lines[#lines + 1] = tostring(a) .. " " .. tostring(c) end
    b:GetScript("OnEnter")(b)
    GameTooltip.AddLine, GameTooltip.AddDoubleLine = was[1], was[2]
    local shown = GameTooltip:IsShown()
    b:GetScript("OnLeave")(b)
    return table.concat(lines, " / "), shown
end

-- MerchantItemButton_OnClick picks the shelf item up with PickupMerchantItem, which
-- sells what the cursor holds; the frame's OnMouseUp and OnReceiveDrag do the same
-- with PickupMerchantItem(0). Held aside, the game's frame can't be reached.
T.test("npc shop game: a click or drop with a bag item on the cursor sells it, never buys", function()
    local N = load()
    NW.Merchant()
    frame(); settle()
    local water = tilesOf(N)[1]
    stub.cursor = { "item", 2589 }
    water:Click("LeftButton")
    T.eq(#NW.Calls("BuyMerchantItem"), 0, "holding an item, a click on a tile doesn't buy")
    T.deq(NW.Calls("PickupMerchantItem"), { { 0 } }, "it sells what's held")
    water:GetScript("OnReceiveDrag")(water)
    T.eq(#NW.Calls("PickupMerchantItem"), 2, "dropped on a tile")
    local page = shop(N)
    T.truthy(page:GetScript("OnReceiveDrag"), "the page takes a drop")
    page:GetScript("OnReceiveDrag")(page)
    page:GetScript("OnMouseUp")(page, "LeftButton")
    T.eq(#NW.Calls("PickupMerchantItem"), 4, "dropped or clicked anywhere on the shop")
    stub.cursor = { "spell", 133 }
    page:GetScript("OnMouseUp")(page, "LeftButton")
    T.eq(#NW.Calls("PickupMerchantItem"), 4, "a spell on the cursor isn't sold")
    stub.cursor = nil
    water:Click("LeftButton")
    T.deq(NW.Calls("BuyMerchantItem"), { { 1 } }, "an empty cursor buys as before")
end)

-- A refundable item is the game's own business (its bags ask before refunding).
T.test("npc shop game: a refundable item on the cursor isn't sold by a drop", function()
    local N = load()
    NW.Merchant()
    frame(); settle()
    MerchantFrame.refundItem = 5
    stub.cursor = { "item", 2589 }
    tilesOf(N)[1]:Click("LeftButton")
    MerchantFrame.refundItem = nil
    stub.cursor = nil
    T.eq(#NW.Calls("PickupMerchantItem"), 0)
    T.eq(#NW.Calls("BuyMerchantItem"), 0)
end)

-- MerchantItemButton_OnEnter: SetMerchantItem, then GameTooltip_ShowCompareItem with no
-- Shift (it compares whatever the tooltip shows). The Buy back tab doesn't compare.
T.test("npc shop game: the shelf's items compare with what you wear, no Shift needed", function()
    local N = load()
    NW.Merchant({ buyback = { { name = "Broken Fang", price = 12 } } })
    frame(); settle()
    gameTip()
    local was = { _G.GameTooltip_ShowCompareItem, _G.IsModifiedClick, GameTooltip.SetMerchantItem, GameTooltip.SetBuybackItem }
    local compared = 0
    _G.GameTooltip_ShowCompareItem = function() compared = compared + 1 end
    _G.IsModifiedClick = function() return false end
    GameTooltip.SetMerchantItem = function() end
    GameTooltip.SetBuybackItem = function() end
    local t = tilesOf(N)[1]
    t:GetScript("OnEnter")(t)
    T.eq(compared, 1, "compared at once")
    t:UpdateTooltip()
    T.eq(compared, 1, "the tooltip's tick doesn't draw it again: the compare stays up")
    t:GetScript("OnLeave")(t)
    shop(N).tabBack:Click()
    frame()
    local b = tilesOf(N)[1]
    b:GetScript("OnEnter")(b)
    T.eq(compared, 1, "a buy-back item doesn't, as the game's")
    b:GetScript("OnLeave")(b)
    _G.GameTooltip_ShowCompareItem, _G.IsModifiedClick, GameTooltip.SetMerchantItem, GameTooltip.SetBuybackItem = unpack(was)
end)

local function footButton(N, word)
    for _, b in ipairs(shop(N).foot.buttons) do
        if b:IsShown() and b.text:GetText():find(word, 1, true) then return b end
    end
end

-- MerchantRepairItemButton_OnClick: the repair cursor for one item, a second press puts it away.
T.test("npc shop game: right-click Repair repairs one item; its hover says so", function()
    local N = load()
    NW.Merchant({ repair = 160 })
    frame(); settle()
    local b = footButton(N, "Repair")
    b:Click("RightButton")
    T.eq(#NW.Calls("ShowRepairCursor"), 1, "the game's repair cursor")
    T.eq(#NW.Calls("RepairAllItems"), 0, "not a repair-all")
    b:Click("RightButton")
    T.eq(#NW.Calls("HideRepairCursor"), 1, "a second right-click puts it away")
    local text, shown = hoverText(b)
    T.truthy(shown, "a hover")
    T.truthy(text:find("repair one item", 1, true), "it says so: " .. text)
    T.truthy(text:find(DaylightUI.MoneyString(160), 1, true), "and what it all costs: " .. text)
end)

-- MerchantGuildBankRepairButton: shown while the guild pays, RepairAllItems(true).
T.test("npc shop game: Guild repair shows only when the guild pays, and repairs with its money", function()
    local N = load()
    NW.Merchant({ repair = 160 })
    frame(); settle()
    T.falsy(footButton(N, "Guild repair"), "no guild: no button")
    NW.Merchant({ repair = 160, guild = { allowance = 100, money = 5000 } })
    frame(); settle()
    local b = footButton(N, "Guild repair")
    T.truthy(b, "the guild pays")
    local words = {}
    for _, x in ipairs(shop(N).foot.buttons) do
        if x:IsShown() then words[#words + 1] = x.text:GetText():match("^(%a[%a ]-)%s*[·|]") or x.text:GetText() end
    end
    T.deq(words, { "Sell junk", "Repair", "Guild repair", "Goodbye" }, "beside Repair, as in the picked mock-up")
    b:Click("LeftButton")
    T.deq(NW.Calls("RepairAllItems"), { { true } })
    local text = hoverText(b)
    T.truthy(text:find(DaylightUI.MoneyString(100), 1, true), "the hover tells what the guild covers: " .. text)
    T.truthy(text:find(DaylightUI.MoneyString(60), 1, true), "and what you pay on top: " .. text)
end)

-- MerchantFrame_OnSellAllJunkButtonClicked asks first (SELL_ALL_JUNK_ITEMS_POPUP).
T.test("npc shop game: Sell junk asks a second click first", function()
    local N = load()
    NW.Merchant({ junk = 2, bags = { [0] = { { quality = 0, sell = 30 }, { quality = 0, sell = 20 } } } })
    frame(); settle()
    local b = footButton(N, "Sell junk")
    T.truthy(b and not b.spec.off, "there's junk")
    b:Click("LeftButton")
    T.eq(#NW.Calls("SellAllJunkItems"), 0, "the first click only asks")
    T.truthy(footButton(N, "Click again"), "and says so")
    footButton(N, "Click again"):Click("LeftButton")
    T.eq(#NW.Calls("SellAllJunkItems"), 0, "a double-click isn't the answer")
    stub.Advance(DaylightUI.Widgets.CONFIRM_GAP + 0.05)
    footButton(N, "Click again"):Click("LeftButton")
    T.eq(#NW.Calls("SellAllJunkItems"), 1, "the second click sells")
    b = footButton(N, "Sell junk")
    b:Click("LeftButton")
    stub.Advance(DaylightUI.Widgets.CONFIRM + 0.1)
    stub.RunTimers()
    T.truthy(footButton(N, "Sell junk"), "asking ends on its own")
end)

T.test("npc shop game: Sell junk's value leaves out bags set to ignore Sell Junk; hidden when the game turns it off", function()
    local N = load()
    NW.Merchant({ junk = 2, bags = { [0] = { { quality = 0, sell = 30 } }, [1] = { { quality = 0, sell = 500 } } }, skip = { [1] = true } })
    frame(); settle()
    local b = footButton(N, "Sell junk")
    T.eq(b.text:GetText(), string.format(DaylightUI.L["Sell junk · %s"], DaylightUI.MoneyString(30)), "only the backpack's")
    NW.Merchant({ junk = 2, sellAllJunk = false, bags = { [0] = { { quality = 0, sell = 30 } } } })
    frame(); settle()
    T.falsy(footButton(N, "Sell junk"), "the game hides it, so does Daylight UI")
end)

T.test("npc shop game: a quest-starting item wears the !, one you can't buy is red, a sold-out one grayed", function()
    local N = load()
    NW.Merchant({ items = { { name = "Old Map", price = 10, quest = true }, { name = "Locked Box", price = 10, purchasable = false },
        { name = "Smallfish", price = 10, available = 0 }, { name = "Jerky", price = 10 } } })
    frame(); settle()
    local t = tilesOf(N)
    T.truthy(t[1].quest and t[1].quest:IsShown(), "the quest mark")
    T.falsy(t[4].quest and t[4].quest:IsShown(), "only there")
    local r, g = t[2].icon:GetVertexColor()
    T.truthy(r > 0.85 and g < 0.25, "not purchasable: red like not usable")
    local sr, sg, sb = t[3].icon:GetVertexColor()
    T.truthy(sr < 0.7 and sg < 0.7 and sb < 0.7 and sr - sg < 0.1, "sold out: dimmed, not red")
    t[3]:Click("LeftButton")
    T.eq(#NW.Calls("BuyMerchantItem"), 0, "and a click doesn't try")
end)

T.test("npc shop game: a currency sold in a container shows the container", function()
    local N = load()
    NW.Merchant({ items = { { name = "Raw", price = 10, currencyID = 42, container = { name = "Pouch of Marks", texture = 99, amount = 3 } } } })
    frame(); settle()
    T.eq(tilesOf(N)[1].name:GetText(), "Pouch of Marks")
end)

-- MerchantFrame_ShowCurrencyTooltip: each currency at the bottom has its tooltip.
T.test("npc shop game: hovering what you hold of a cost shows its tooltip", function()
    local N = load()
    local count = C_Item.GetItemCount
    C_Item.GetItemCount = function() return 7 end
    NW.Merchant({ items = { { name = "Pattern", price = 0, extended = true,
        costs = { { texture = 132889, value = 3, link = "|Hitem:2589|h[Linen Cloth]|h" } } } } })
    frame(); settle()
    C_Item.GetItemCount = count
    gameTip()
    local hits = N.frame.walletHits or {}
    T.truthy(hits[1] and hits[1]:IsShown(), "a hover spot over the piece")
    local was, linked = GameTooltip.SetHyperlink, nil
    GameTooltip.SetHyperlink = function(_, l) linked = l end
    hits[1]:GetScript("OnEnter")(hits[1])
    GameTooltip.SetHyperlink = was
    T.eq(linked, "|Hitem:2589|h[Linen Cloth]|h")
    hits[1]:GetScript("OnLeave")(hits[1])
end)

T.test("npc shop game: dragging a buy-back item buys it back", function()
    local N = load()
    NW.Merchant({ buyback = { { name = "Broken Fang", price = 12 } } })
    frame(); settle()
    shop(N).tabBack:Click()
    frame()
    local b = tilesOf(N)[1]
    b:GetScript("OnDragStart")(b)
    T.deq(NW.Calls("BuybackItem"), { { 1 } })
end)

T.test("npc shop game: a gear change refills the shelf (UNIT_INVENTORY_CHANGED)", function()
    local N = load()
    NW.Merchant()
    frame(); settle()
    NW.state.merchant.items[1].usable = false
    stub.FireEvent("UNIT_INVENTORY_CHANGED", "player")
    frame()
    local r, g = tilesOf(N)[1].icon:GetVertexColor()
    T.truthy(r > 0.85 and g < 0.25, "the water now reads unusable")
end)

T.test("npc shop game: on a controller LB and RB switch Shop and Buy back", function()
    local N = load()
    NW.Merchant({ buyback = { { name = "Broken Fang", price = 12 } } })
    frame(); settle()
    T.eq(type(N.frame.padTabs), "function", "the window lists its tabs")
    local list, at = N.frame.padTabs()
    T.eq(#list, 2)
    T.eq(at, 1)
    list[2]:Click()
    T.eq(stub.npc.Shop.state.tab, "back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("npc shop game: setting a bag to ignore Sell Junk at the vendor updates the value at once", function()
    local N = load()
    NW.Merchant({ junk = 2, bags = { [0] = { { quality = 0, sell = 30 } }, [1] = { { quality = 0, sell = 500 } } } })
    frame(); settle()
    NW.state.merchant.skip = { [1] = true }
    stub.FireEvent("BAG_SLOT_FLAGS_UPDATED", 1)
    frame()
    T.eq(footButton(N, "Sell junk").text:GetText(), string.format(DaylightUI.L["Sell junk · %s"], DaylightUI.MoneyString(30)))
end)

-- ---------------------------------------------------------------------
-- Talk and quest pages: what the game's own GossipFrame, QuestFrame and
-- QuestInfo.lua do (audit S4)
-- ---------------------------------------------------------------------

local function talk(N) return N.frame.pages.talk end
-- Every piece of the talk page: its words (a text, a tile's name) and the piece.
local function talkPieces(N)
    local out = {}
    for _, p in ipairs(talk(N).pieces or {}) do
        local fs = p.name or p.text
        out[#out + 1] = { text = fs and fs.GetText and fs:GetText() or "", piece = p }
    end
    return out
end
local function talkFind(N, word)
    for _, e in ipairs(talkPieces(N)) do
        if e.text:find(word, 1, true) then return e.piece, e.text end
    end
end
local function talkButton(N, word)
    for _, b in ipairs(talk(N).foot.buttons) do
        if b:IsShown() and b.text:GetText():find(word, 1, true) then return b end
    end
end

-- QuestInfoRewardItemMixin:OnEnter and QuestItemTemplate call GameTooltip_ShowCompareItem
-- on every item hover, Shift or not; a currency never compares.
T.test("npc talk game: reward and required items compare with your gear without Shift", function()
    local N = load()
    gameTip()
    local was = { _G.GameTooltip_ShowCompareItem, _G.IsModifiedClick, GameTooltip.SetQuestItem, GameTooltip.SetQuestCurrency }
    local compared = 0
    _G.GameTooltip_ShowCompareItem = function() compared = compared + 1 end
    _G.IsModifiedClick = function() return false end
    GameTooltip.SetQuestItem = function() end
    GameTooltip.SetQuestCurrency = function() end
    NW.Quest("COMPLETE", NW.Candles({ currencies = { { name = "Marks of Honor", count = 2 } } }))
    frame(); settle()
    local boots = talkFind(N, "Walking Boots")
    boots:GetScript("OnEnter")(boots)
    T.eq(compared, 1, "a reward compares at once")
    boots:GetScript("OnLeave")(boots)
    local marks = talkFind(N, "Marks of Honor")
    marks:GetScript("OnEnter")(marks)
    T.eq(compared, 1, "a currency doesn't")
    marks:GetScript("OnLeave")(marks)
    NW.Quest("PROGRESS", NW.Candles())
    frame(); settle()
    local candle = talkFind(N, "Large Candle")
    candle:GetScript("OnEnter")(candle)
    T.eq(compared, 2, "a required item does too")
    candle:GetScript("OnLeave")(candle)
    _G.GameTooltip_ShowCompareItem, _G.IsModifiedClick, GameTooltip.SetQuestItem, GameTooltip.SetQuestCurrency = unpack(was)
end)

-- QuestInfo_ShowRewards: spells the quest teaches or casts (not ones you know), a title,
-- skill points and honor all show; a spell's hover is SetSpellByID, Shift links it.
T.test("npc talk game: a quest that teaches a spell shows it, with its hover and Shift link", function()
    local N = load()
    local q = NW.Candles({ choices = {}, money = 0, xp = 0, spells = {
        { spellID = 1066, name = "Aquatic Form", type = 5 },
        { spellID = 9999, name = "Already Known", type = 5, known = true },
        { spellID = 2000, name = "Blessing of the Grove", type = 4 } } })
    NW.Quest("DETAIL", q)
    frame(); settle()
    local form = talkFind(N, "Aquatic Form")
    T.truthy(form, "the spell is on the offer")
    T.isnil(talkFind(N, "Already Known"), "a spell you know isn't, as the game's")
    T.truthy(talkFind(N, "Blessing of the Grove"), "a spell cast on you is")
    gameTip()
    local spell
    local wasSet = GameTooltip.SetSpellByID
    GameTooltip.SetSpellByID = function(_, id) spell = id end
    form:GetScript("OnEnter")(form)
    T.eq(spell, 1066, "its hover is the spell's tooltip")
    form:GetScript("OnLeave")(form)
    GameTooltip.SetSpellByID = wasSet
    local linked
    local was = { _G.IsModifiedClick, _G.HandleModifiedItemClick }
    _G.IsModifiedClick = function(m) return m == "CHATLINK" end
    _G.HandleModifiedItemClick = function(link) linked = link; return true end
    form:Click()
    T.truthy(linked and linked:find("spell:1066", 1, true), "Shift-click links the spell")
    _G.IsModifiedClick, _G.HandleModifiedItemClick = was[1], was[2]
    NW.Quest("COMPLETE", q)
    frame(); settle()
    T.truthy(talkFind(N, "Aquatic Form"), "and on the hand-in")
end)

T.test("npc talk game: a title, skill points and honor show among the rewards", function()
    local N = load()
    NW.Quest("COMPLETE", NW.Candles({ choices = {}, rewardTitle = "the Patient", honor = 150,
        skill = { name = "Fishing", icon = 136245, points = 5 } }))
    frame(); settle()
    T.truthy(talkFind(N, "the Patient"), "the title")
    T.truthy(talkFind(N, "Fishing"), "the skill points")
    local honor = talkFind(N, HONOR or DaylightUI.L["Honor"])
    T.truthy(honor, "the honor")
    T.eq(honor and honor.count:GetText(), "150")
end)

T.test("npc talk game: a spell learned meanwhile drops off the offer (LEARNED_SPELL_IN_SKILL_LINE)", function()
    local N = load()
    local q = NW.Candles({ spells = { { spellID = 1066, name = "Aquatic Form", type = 5 } } })
    NW.Quest("DETAIL", q)
    frame(); settle()
    T.truthy(talkFind(N, "Aquatic Form"))
    q.spells[1].known = true
    stub.FireEvent("LEARNED_SPELL_IN_SKILL_LINE", 1066)
    frame(2)
    T.isnil(talkFind(N, "Aquatic Form"), "gone once known")
end)

-- QuestInfo_ShowGroupSize and QuestInfo_ShowSpecialObjectives on the offer.
T.test("npc talk game: the offer says how many players it suggests and a spell to learn", function()
    local N = load()
    NW.Quest("DETAIL", NW.Candles({ group = 3, criteria = { spellID = 818, name = "Basic Campfire" } }))
    frame(); settle()
    local want = string.format(QUEST_SUGGESTED_GROUP_NUM or DaylightUI.L["Suggested players: %d"], 3)
    T.truthy(talkFind(N, want), "suggested players")
    T.truthy(talkFind(N, "Basic Campfire"), "the spell to learn")
end)

-- QuestFrameProgressItems_Update: required currencies, the offer's hide flag, an item
-- whose name hasn't come yet still has its slot, the money red when you're short.
T.test("npc talk game: the turn-in page lists required currencies with their tooltip", function()
    local N = load()
    NW.Quest("PROGRESS", NW.Candles({ requiredCurrencies = { { name = "Timbermaw Token", count = 4 } } }))
    frame(); settle()
    local token = talkFind(N, "Timbermaw Token")
    T.truthy(token, "the currency is listed")
    gameTip()
    local asked
    local was = GameTooltip.SetQuestCurrency
    GameTooltip.SetQuestCurrency = function(_, kind, i) asked = kind .. i end
    if token then
        token:GetScript("OnEnter")(token)
        token:GetScript("OnLeave")(token)
    end
    GameTooltip.SetQuestCurrency = was
    T.eq(asked, "required1")
end)

T.test("npc talk game: required items stay hidden when the offer hides them", function()
    local N = load()
    NW.Quest("PROGRESS", NW.Candles({ hideRequired = true }))
    frame(); settle()
    T.isnil(talkFind(N, "Large Candle"))
end)

T.test("npc talk game: a required item still loading keeps its slot", function()
    local N = load()
    NW.Quest("PROGRESS", NW.Candles({ required = { { name = "Large Candle", loading = true, count = 8, itemID = 77 } } }))
    frame(); settle()
    T.truthy(talkFind(N, RETRIEVING_ITEM_INFO or DaylightUI.L["Loading..."]), "a loading tile")
end)

T.test("npc talk game: required money is red when you can't pay it", function()
    local N = load()
    local was = _G.GetMoney
    _G.GetMoney = function() return 50 end
    NW.Quest("PROGRESS", NW.Candles({ required = {}, cost = 500 }))
    frame(); settle()
    local _, text = talkFind(N, DaylightUI.MoneyString(500))
    T.truthy(text, "the money shows")
    T.truthy(text and text:find(DaylightUI.Win.Parts.Hex(DaylightUI.Style.INK.BAD), 1, true), "in red")
    _G.GetMoney = was
end)

-- QuestFrame_OnHide hides QuestFrame.dialog: the PvP question leaves with the window,
-- and never sends DeclineQuest after the talk is over.
T.test("npc talk game: the PvP question goes away with the window", function()
    local N = load()
    NW.Quest("DETAIL", NW.Candles({ pvp = true }))
    frame(); settle()
    talkButton(N, DaylightUI.L["Accept"]):Click()
    T.truthy(DaylightUI.Widgets.Asking(), "it asks")
    NW.Escape()
    frame(3)
    T.isnil(DaylightUI.Widgets.Asking(), "gone with the window")
    T.eq(#NW.Calls("DeclineQuest"), 0, "and never declines afterwards")
end)

-- QuestFrame_SetPortrait: the quest pages are "questnpc": a quest a party member shares.
T.test("npc talk game: a quest page names who gives it (questnpc)", function()
    stub.Load({ before = NW.world({ npc = { questnpc = { name = "Ardent Friend", reaction = 5 } } }) })
    local N = stub.npc.Window
    NW.Quest("DETAIL", NW.Candles())
    frame(); settle()
    T.eq(N.frame.title:GetText(), "Ardent Friend")
end)

-- QuestFrame_OnEvent and the portrait template listen for UNIT_PORTRAIT_UPDATE.
T.test("npc talk game: the portrait is drawn again when the NPC's portrait loads", function()
    load()
    NW.Gossip(GOSSIP)
    frame(); settle()
    local drawn = 0
    local was = _G.SetPortraitTexture
    _G.SetPortraitTexture = function(...) drawn = drawn + 1; return was(...) end
    stub.FireEvent("UNIT_PORTRAIT_UPDATE", "npc")
    frame()
    _G.SetPortraitTexture = was
    T.truthy(drawn > 0, "drawn again")
end)

-- QuestFrame_OnEvent: QUEST_LOG_UPDATE refreshes the greeting; GossipFrame only
-- refreshes on it while it lists quests.
T.test("npc talk game: the quest greeting refreshes when your quest log changes", function()
    local N = load()
    NW.Quest("GREETING", { text = "Hail.", active = { { title = "Kobold Candles", questID = 60 } } })
    frame(); settle()
    NW.state.greeting.active[1].isComplete = true
    stub.FireEvent("QUEST_LOG_UPDATE")
    frame(2)
    T.eq(N.state.data.quests[1].complete, true, "ready now")
end)

T.test("npc talk game: a gossip without quests doesn't redraw on every quest log update", function()
    local N = load()
    NW.Gossip({ text = "Hello.", options = { { name = "Make this inn your home.", icon = 1 } } })
    frame(); settle()
    local before = N.state.data
    stub.FireEvent("QUEST_LOG_UPDATE")
    frame(2)
    T.eq(N.state.data, before, "not read again")
end)

-- QuestUtil.ApplyQuestIconOfferToTextureForQuestID: a repeatable quest wears the blue "!".
T.test("npc talk game: a repeatable quest wears the game's repeatable mark, a trivial one is dimmed", function()
    local N = load()
    NW.Gossip({ text = "Hi.", available = { { title = "Again", questID = 70, repeatable = true },
        { title = "Easy", questID = 71, isTrivial = true }, { title = "Plain", questID = 72 } } })
    frame(); settle()
    T.eq(N.rows[1].icon.__texture, "Interface/GossipFrame/DailyActiveQuestIcon", "repeatable")
    local r = N.rows[2].icon:GetVertexColor()
    T.truthy(r < 1, "trivial dimmed")
    T.eq(N.rows[3].icon.__atlas, "QuestNormal", "a plain one keeps the gold !")
end)

-- GossipOptionButtonMixin:Setup: GOSSIP_OPTION_PREPEND with QUEST_PREPEND and PLAY_MOVIE_PREPEND.
T.test("npc talk game: a gossip option marked as a quest or a movie says so, both when both", function()
    local was = { _G.GOSSIP_OPTION_PREPEND, _G.QUEST_PREPEND, _G.PLAY_MOVIE_PREPEND }
    _G.GOSSIP_OPTION_PREPEND, _G.QUEST_PREPEND, _G.PLAY_MOVIE_PREPEND = "%s %s", "(Quest)", "(Movie)"
    local N = load()
    local wasFlags = Enum.GossipOptionRecFlags
    Enum.GossipOptionRecFlags = { QuestLabelPrepend = 1, PlayMovieLabelPrepend = 2 }
    NW.Gossip({ text = "Hi.", options = { { name = "Tell me more.", icon = 1, flags = 1 }, { name = "Watch it.", icon = 2, flags = 3 } } })
    frame(); settle()
    local t = texts(N)
    T.eq(t[1], "(Quest) Tell me more.")
    T.eq(t[2], "(Quest) (Movie) Watch it.")
    _G.GOSSIP_OPTION_PREPEND, _G.QUEST_PREPEND, _G.PLAY_MOVIE_PREPEND = unpack(was)
    Enum.GossipOptionRecFlags = wasFlags
end)

-- Under the game's window sounds the talk window plays QuestFrame's kits: the quest list
-- opening and closing, IG_QUEST_CANCEL on Decline, IG_QUEST_LIST_SELECT on a greeting
-- quest, IG_QUEST_LIST_OPEN on Continue.
T.test("npc talk game: under the game's sounds the talk window plays the quest window's", function()
    local N = load()
    DaylightUI:Set("general", "soundKinds.windows", "game")
    DaylightUI:Set("general", "soundKinds.clicks", "game")
    stub.RunTimers()
    local kits = {}
    _G.SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 1, IG_CHARACTER_INFO_CLOSE = 2, IG_MAINMENU_OPTION = 3,
        IG_QUEST_LIST_OPEN = 10, IG_QUEST_LIST_CLOSE = 11, IG_QUEST_CANCEL = 12, IG_QUEST_LIST_SELECT = 13 }
    _G.PlaySound = function(kit) kits[#kits + 1] = kit end
    local function heard(k) for _, x in ipairs(kits) do if x == k then return true end end return false end
    stub.Advance(1)
    NW.Quest("GREETING", { text = "Hail.", available = { { title = "Kobold Candles", questID = 60 } } })
    frame(); settle()
    T.truthy(heard(10), "the quest list opens")
    T.truthy(not heard(1), "not the character window's")
    stub.Advance(1)
    N.rows[1]:Click()
    T.truthy(heard(13), "picking a quest")
    stub.Advance(1)
    NW.Quest("PROGRESS", NW.Candles())
    frame(); settle()
    kits = {}
    talkButton(N, CONTINUE or DaylightUI.L["Continue"]):Click()
    T.truthy(heard(10), "Continue")
    stub.Advance(1)
    NW.Quest("DETAIL", NW.Candles())
    frame(); settle()
    kits = {}
    talkButton(N, DaylightUI.L["Decline"]):Click()
    frame(); settle()
    T.truthy(heard(12), "Decline")
    T.truthy(heard(11), "the quest list closes")
    T.truthy(not heard(2), "not the character window's")
    _G.SOUNDKIT, _G.PlaySound = nil, nil
end)

-- QuestFrame_OnHide: an auto-accepted quest's window closing plays PlayAutoAcceptQuestSound.
T.test("npc talk game: an auto-accepted quest plays the game's sound as it closes", function()
    local N = load()
    local played = 0
    _G.PlayAutoAcceptQuestSound = function() played = played + 1 end
    NW.Quest("DETAIL", NW.Candles({ auto = true }))
    frame(); settle()
    talkButton(N, OKAY or DaylightUI.L["Okay"]):Click()
    frame(3)
    T.eq(played, 1)
    _G.PlayAutoAcceptQuestSound = nil
end)
