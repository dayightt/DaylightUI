local stub = require("stub")
local LW = require("legacyworld")

-- The Legacy window.

local function load(spec)
    stub.Load({ before = LW.world(spec) })
    return stub.legacy
end

-- A frame of the world: timers, the follower's look, the moves.
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

local function open(ns, how)
    if how == "challenges" then LW.Challenges() else LW.Toggle() end
    frame(20)
    return ns.Window.frame
end

local function tab(ns, id)
    stub.Key(function() ns.Window.ShowTab(id) end)
    frame(20)
end

local function plain(text) return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function clean()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end

local function shownOf(stack, kind)
    local out = {}
    for _, b in ipairs(stack.used) do
        if b:IsShown() and (not kind or (b.spec and b.spec.kind == kind) or (kind == "ch" and b.ch)) then out[#out + 1] = b end
    end
    return out
end

-- ---------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------

T.test("legacy: on by default, built at login, the game's addon never loaded by us", function()
    local ns = load()
    T.eq(DaylightUI.legacyOwnWindow, true)
    T.truthy(ns.Window.frame, "built")
    T.eq(#LW.Calls("LoadLegacy"), 0, "the game loads its own window when it's opened")
    clean()
end)

T.test("legacy: switched off, the game's window stays the game's", function()
    local ns = load({ enabled = false })
    T.isnil(ns.Window.frame, "nothing built")
    LW.Toggle()
    frame(5)
    T.eq(LegacySystemFrame:GetParent(), UIParent, "not parked")
    T.truthy(LegacySystemFrame:IsVisible())
end)

T.test("legacy: the Legacy button opens ours in the game's place, on Progress, with points in the header", function()
    local ns = load()
    local f = open(ns)
    T.truthy(DaylightUI.Win.IsOpen(f), "ours open")
    T.eq(LegacySystemFrame:GetParent(), DaylightUI.Win.Followers.hidden, "parked as it loaded")
    T.eq(f.tab, "progress")
    T.eq(#f.tabs, 3)
    T.eq(f.title:GetText(), "Legacy")
    T.eq(plain(f.sub:GetText()), "16 Legacy Points  ·  3 to spend")
    clean()
end)

T.test("legacy: the achievement key opens ours on Challenges; again closes it", function()
    local ns = load()
    local f = open(ns, "challenges")
    T.eq(f.tab, "challenges")
    LW.Challenges()
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f), "closed with the game's")
    clean()
end)

T.test("legacy: our X closes the game's window too", function()
    local ns = load()
    local f = open(ns)
    f.onClose()
    frame(20)
    T.falsy(LegacySystemFrame:IsShown())
    T.falsy(DaylightUI.Win.IsOpen(f))
    clean()
end)

-- ---------------------------------------------------------------------
-- Progress
-- ---------------------------------------------------------------------

T.test("legacy progress: the ring, the next reward, the cards and the bar", function()
    local ns = load()
    open(ns)
    local page = ns.Progress.page
    T.eq(page.medal.num:GetText(), "16")
    T.eq(plain(page.next:GetText()), "Next: Spectral Bear Cub at 25, 9 to go")
    local cards = {}
    for _, b in ipairs(page.cards) do if b:IsShown() then cards[#cards + 1] = b end end
    T.eq(#cards, 4)
    T.eq(cards[1].name:GetText(), "Holstered Replica Ironforge Air Rifle")
    T.eq(cards[1].kind:GetText(), "Toy")
    T.eq(cards[2].kind:GetText(), "Pet")
    T.eq(cards[3].kind:GetText(), "Tabard")
    T.eq(cards[4].kind:GetText(), "Mount")
    T.eq(cards[1].state:GetText(), "Earned")
    T.eq(plain(cards[2].state:GetText()), "9 more")
    T.truthy(cards[1].lit:IsShown(), "an earned card's accent line")
    T.falsy(cards[2].lit:IsShown())
    -- Past the first card by 1 of 10 points toward the second.
    local v = page.bar:GetValue()
    T.truthy(v > 0.12 and v < 0.2, tostring(v))
    T.near(page.medal.at, 0.1, 0.001)
    clean()
end)

T.test("legacy progress: points arriving count up, the ring and bar glide, a reached reward shines", function()
    local ns = load()
    open(ns)
    local page = ns.Progress.page
    local before = page.bar:GetValue()
    LW.Earn(10)
    frame(2)
    local mid = tonumber(page.medal.num:GetText())
    T.truthy(mid and mid >= 16 and mid <= 26, tostring(mid))
    frame(30)
    T.eq(page.medal.num:GetText(), "26")
    T.truthy(page.bar:GetValue() > before)
    T.eq(page.cards[2].state:GetText(), "Earned")
    T.eq(plain(ns.Window.frame.sub:GetText()), "26 Legacy Points  ·  13 to spend")
    clean()
end)

T.test("legacy progress: more than four rewards glide sideways on the wheel", function()
    local levels = LW.Levels()
    levels[5] = { level = 70, rewards = { { itemID = 504, name = "Spectral Crown", icon = 1005, rewardType = 1 } } }
    levels[6] = { level = 85, rewards = { { itemID = 505, name = "Spectral Throne", icon = 1006, rewardType = 1 } } }
    local ns = load({ levels = levels })
    open(ns)
    local P = ns.Progress
    T.eq(P.off, 0, "the next reward (the second) shows with the one before it")
    P.Wheel(-1)
    frame(20)
    T.eq(P.off, 1)
    P.Wheel(-5)
    frame(20)
    T.eq(P.off, 2, "never past the last four")
    clean()
end)

-- A tooltip that keeps its lines (the fake game has none of its own).
local function fakeTip()
    local tip = CreateFrame("Frame", "GameTooltip", UIParent)
    _G.GameTooltip = tip
    function tip:SetOwner(o) self.__owner, self.__lines = o, {} end
    function tip:IsOwned(o) return self.__owner == o end
    function tip:SetItemByID(id) self.__item = id end
    function tip:AddLine(t) self.__lines[#self.__lines + 1] = plain(tostring(t)) end
    function tip:AddDoubleLine(l) self.__lines[#self.__lines + 1] = plain(tostring(l)) end
    return tip
end

T.test("legacy progress: hover shows the item's own tooltip and how far", function()
    local ns = load()
    fakeTip()
    open(ns)
    local card = ns.Progress.page.cards[2]
    card:GetScript("OnEnter")(card)
    T.eq(GameTooltip.__item, 502, "the game's item tooltip")
    local text = table.concat(GameTooltip.__lines, " | ")
    T.truthy(text:find("Legacy reward at 25", 1, true), text)
    T.truthy(text:find("9 more Legacy Points", 1, true), text)
    _G.GameTooltip = nil
    clean()
end)

-- ---------------------------------------------------------------------
-- Challenges
-- ---------------------------------------------------------------------

T.test("legacy challenges: opens on your class's category, done ones first, points and dates", function()
    local ns = load()
    stub.SetUnits({ player = { class = "MAGE" } })
    local f = open(ns, "challenges")
    local C = ns.Challenges
    T.eq(C.cat, 11, "the game's default for a Mage")
    local rows = shownOf(C.page.list, "ch")
    T.eq(#rows, 3)
    T.eq(rows[1].ch.name, "Arcane Initiate")
    T.eq(plain(rows[1].points:GetText()), "+2")
    T.truthy(rows[1].date:GetText() ~= "", "a done one's date")
    T.falsy(rows[2].ch.done)
    T.falsy(C.list[3].done, "earned by another character counts as not done")
    T.truthy(plain(C.page.sumValue:GetText()):find("16 / 140", 1, true), plain(C.page.sumValue:GetText()))
    clean()
end)

-- Matches the game's GetChallengeIndices. "Not yet" skips the done range, which
-- also holds ones earned by other characters. "Done" keeps only your own.
T.test("legacy challenges: the chips filter the game's way", function()
    local ns = load()
    local f = open(ns, "challenges")
    local C = ns.Challenges
    C.Pick(11)
    C.Filter("todo")
    frame(2)
    local names = {}
    for _, c in ipairs(C.list) do names[#names + 1] = c.name end
    T.eq(table.concat(names, ", "), "Portal Master")
    C.Filter("done")
    frame(2)
    names = {}
    for _, c in ipairs(C.list) do names[#names + 1] = c.name end
    T.eq(table.concat(names, ", "), "Arcane Initiate")
    clean()
end)

T.test("legacy challenges: a click opens its steps; the track switch tracks it", function()
    local ns = load()
    open(ns, "challenges")
    local C = ns.Challenges
    C.Pick(11)
    frame(2)
    local function portal()
        for _, b in ipairs(shownOf(C.page.list, "ch")) do if b.ch.name == "Portal Master" then return b end end
    end
    local row = portal()
    row:GetScript("OnClick")(row)
    frame(10)
    row = portal()
    T.truthy(row.more:IsShown(), "opened")
    T.truthy(row:GetHeight() > C.ROW, "taller when open")
    T.eq(row.steps[1].text:GetText(), "Stormwind")
    T.truthy(row.track:IsShown())
    row.track:GetScript("OnClick")(row.track)
    T.eq(#LW.Calls("StartTracking"), 1)
    clean()
end)

T.test("legacy challenges: the search is the client's, answered a frame later", function()
    local ns = load()
    open(ns, "challenges")
    local C = ns.Challenges
    C.page.search:SetText("tanaris")
    stub.Key(function() C.page.search:GetScript("OnTextChanged")(C.page.search, true) end)
    frame(3)
    T.eq(C.cat, 20, "the category holding it")
    T.eq(#C.list, 1)
    T.eq(C.list[1].name, "Explore Tanaris")
    clean()
end)

T.test("legacy challenges: a newly earned one marks its category and the tab until looked at", function()
    local ns = load()
    local f = open(ns)
    LW.Complete(2002)
    frame(3)
    T.truthy(plain(f.tabs[2].text:GetText()):find("Challenges 1", 1, true), plain(f.tabs[2].text:GetText()))
    tab(ns, "challenges")
    ns.Challenges.Pick(20)
    frame(3)
    T.eq(plain(f.tabs[2].text:GetText()), "Challenges")
    clean()
end)

T.test("legacy challenges: a tracked challenge's click opens ours on it", function()
    local ns = load()
    local f = open(ns)
    LW.Show(1201)
    frame(20)
    T.eq(f.tab, "challenges")
    T.eq(ns.Challenges.cat, 12)
    T.eq(ns.Challenges.opened, 1201)
    clean()
end)

-- ---------------------------------------------------------------------
-- Legacy trees
-- ---------------------------------------------------------------------

local function tileOf(ns, id)
    for _, b in ipairs(ns.Trees.page.box.tiles) do if b:IsShown() and b.node and b.node.id == id then return b end end
end

T.test("legacy trees: three trees, spent and to spend; the tree on the spellbook's tiles", function()
    local ns = load()
    open(ns)
    tab(ns, "trees")
    local page = ns.Trees.page
    local lines = {}
    for _, b in ipairs(page.list.used) do if b:IsShown() and b.lineSpec then lines[#lines + 1] = b.name:GetText() .. " " .. plain(b.sub:GetText()) end end
    T.eq(table.concat(lines, " | "), "Professions 2 spent | Adventure 1 spent | Progression 0 spent")
    T.eq(page.left:GetText(), "3")
    local t = tileOf(ns, 7101)
    T.truthy(t, "a tile")
    T.eq(t.node.col, 0)
    T.eq(t.node.row, 0)
    T.eq(tileOf(ns, 7106).node.row, 3, "the grid's step read from the nodes (400 here)")
    T.eq(tileOf(ns, 7105).node.col, 1)
    clean()
end)

T.test("legacy trees: a click stages a point, Undo takes it back", function()
    local ns = load()
    open(ns)
    tab(ns, "trees")
    local t = tileOf(ns, 7101)
    stub.Key(function() t:GetScript("OnClick")(t, "LeftButton") end)
    frame(3)
    T.eq(#LW.Calls("PurchaseRank"), 1)
    t = tileOf(ns, 7101)
    T.eq(t.node.rank, 3)
    T.truthy(t.node.staged, "green until Apply")
    T.eq(ns.Trees.page.left:GetText(), "2")
    local undo = ns.Trees.page.foot.buttons[2]
    T.falsy(undo.spec.off)
    undo.spec.onClick(undo)
    frame(3)
    T.eq(tileOf(ns, 7101).node.rank, 2)
    clean()
end)

T.test("legacy trees: Apply commits the tree's config; the gold light rolls once the server says yes", function()
    local ns = load()
    open(ns)
    tab(ns, "trees")
    local t = tileOf(ns, 7102)
    stub.Key(function() t:GetScript("OnClick")(t, "LeftButton") end)
    frame(3)
    local apply = ns.Trees.page.foot.buttons[1]
    T.falsy(apply.spec.off)
    local heard = {}
    _G.PlaySoundFile = function(file) heard[#heard + 1] = file end
    apply.spec.onClick(apply)
    T.eq(LW.Calls("CommitConfig")[1][1], LW.CONFIG(LW.PROF))
    stub.Advance(LW.COMMIT_DELAY + 0.1)
    frame(40)
    local n = 0
    for _, f in ipairs(heard) do if f == DaylightUI.Sound.FILES.apply then n = n + 1 end end
    _G.PlaySoundFile = nil
    T.eq(n, 1, "the chime")
    T.isnil(ns.Trees.committing)
    T.falsy(tileOf(ns, 7102).node.staged)
    T.eq(LW.Node(7102).applied, 1)
    clean()
end)

T.test("legacy trees: a choice node asks which, through our menu", function()
    local nodes = LW.Trees()
    nodes[LW.PROF].nodes[6].x = 1000   -- open from the start: no arrow into it
    nodes[LW.PROF].nodes[5].edges = nil
    local ns = load({ trees = nodes })
    open(ns)
    tab(ns, "trees")
    local W = DaylightUI.Widgets
    local seen
    local real = W.OpenMenu
    W.OpenMenu = function(_, keys, values, _, pick) seen = { keys = keys, values = values, pick = pick } end
    local t = tileOf(ns, 7106)
    stub.Key(function() t:GetScript("OnClick")(t, "LeftButton") end)
    W.OpenMenu = real
    T.truthy(seen, "our menu")
    T.eq(#seen.keys, 2)
    T.eq(seen.values[71061], "Perk 71061")
    seen.pick(71062)
    frame(3)
    T.eq(LW.Calls("SetSelection")[1][3], 71062)
    T.eq(LW.Node(7106).rank, 1)
    clean()
end)

T.test("legacy trees: switching trees shows the other tree", function()
    local ns = load()
    open(ns)
    tab(ns, "trees")
    ns.Trees.Pick(2)
    frame(10)
    T.truthy(tileOf(ns, 7201))
    T.isnil(tileOf(ns, 7101))
    clean()
end)

T.test("legacy trees: Reset tree asks first, then resets through the game", function()
    local ns = load()
    open(ns)
    tab(ns, "trees")
    local b = ns.Trees.page.reset
    b:GetScript("OnClick")(b)
    T.eq(#LW.Calls("ResetTree"), 0, "first click arms it")
    stub.Advance(1)   -- past W.CONFIRM_GAP: a real second click, not a double-click
    b:GetScript("OnClick")(b)
    T.eq(#LW.Calls("ResetTree"), 1)
    clean()
end)

-- The game's Legacy window hides Reset on a tree flagged cannotRefund, since its
-- points only come back at the NPC for gold. This one never offers it either.
T.test("legacy trees: a tree that can't be refunded has no Reset tree", function()
    local ns = load({ cannotRefund = true })
    open(ns)
    tab(ns, "trees")
    local b = ns.Trees.page.reset
    T.falsy(b:IsShown(), "no Reset tree button, as in the game's window")
    T.eq(ns.Trees.Spend.Reset(), false)
    T.eq(#LW.Calls("ResetTree"), 0)
    clean()
end)

T.test("legacy on a controller: X links a challenge; in a tree A adds, Y takes a point back, as the game's", function()
    local ns = load()
    local f = open(ns, "challenges")
    local C = ns.Challenges
    C.Pick(11)
    frame(2)
    local row = shownOf(C.page.list, "ch")[1]
    local function on(key, b)
        for _, e in ipairs(f.padKeys) do if e.key == key and (not e.when or e.when(b)) then return e end end
    end
    T.eq(on("X", row).label, SOCIAL_SHARE_TEXT or "Link in chat")
    T.truthy(on("MENU_LEFT", row), "the menu button searches")
    tab(ns, "trees")
    local t = tileOf(ns, 7101)
    T.eq(f.padSelect(t), GAMEPAD_TALENT_ADD_POINT or "Add point")
    T.falsy(on("X", t), "nothing to apply yet")
    clean()
end)
