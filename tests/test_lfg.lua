local stub = require("stub")
local LW = require("lfgworld")

-- The group finder window.

-- Whisper buttons ask in Daylight UI's own box (Pad.Whisper, no chat module
-- here) and never open the game's chat box. The questions asked, in order.
local function whispers()
    local asked = {}
    DaylightUI.Widgets.Prompt = function(text) asked[#asked + 1] = text end
    return asked
end

local function load(spec)
    stub.Load({ before = LW.world(spec) })
    return stub.lfg
end

-- Advances one game frame: timers, the follower, the moves.
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

-- The game's key binding (LFGVanilla_ToggleFrame(1)) opens this window instead.
local function open(ns)
    LW.Toggle(1)
    frame(20)
    return ns.Window.frame
end

-- Clicks a tab as the player would.
local function tab(ns, id)
    stub.Key(function() ns.Window.ShowTab(id, true) end)
    frame(20)
end

local function rows(stack, kind)
    local out = {}
    for _, b in ipairs(stack.used) do
        if b:IsShown() and b.spec and b.spec.kind == kind then out[#out + 1] = b end
    end
    return out
end

local function texts(list, field)
    local out = {}
    for _, b in ipairs(list) do out[#out + 1] = b[field or "name"]:GetText() end
    return table.concat(out, " | ")
end

-- What a detail card shows: its shown lines as { label = value } (a line with no title is
-- keyed by its position), and its shown buttons' texts.
local function card(detail)
    local lines, buttons = {}, {}
    local people = {}
    for _, m in ipairs(detail.people) do
        if m:IsShown() then people[#people + 1] = m.name:GetText() .. " " .. m.level:GetText() end
    end
    for i, r in ipairs(detail.rows) do
        if r.value:IsShown() then
            local label = r.label:IsShown() and r.label:GetText() or ("#" .. i)
            lines[label] = r.value:GetText()
        elseif r.label:IsShown() and #people > 0 then
            lines[r.label:GetText()] = table.concat(people, string.char(10))   -- a row of people: one line each
        end
    end
    for _, b in ipairs(detail.buttons) do if b:IsShown() then buttons[#buttons + 1] = b.text:GetText() end end
    return lines, buttons
end

local function click(row)
    stub.Key(function() row:GetScript("OnClick")(row, "LeftButton") end)
    frame(20)
end

local function blocked()
    for _, e in ipairs(stub.errors) do if tostring(e):find("ADDON_ACTION_BLOCKED", 1, true) then return e end end
    return nil
end

-- GameTooltip's lines, as text.
local function recordTips()
    _G.GameTooltip = _G.GameTooltip or CreateFrame("GameTooltip", "GameTooltip", UIParent)
    local tip = GameTooltip
    tip.lines = {}
    tip.AddLine = function(self, t) self.lines[#self.lines + 1] = tostring(t) end
    tip.AddDoubleLine = function(self, l, r) self.lines[#self.lines + 1] = tostring(l) .. " = " .. tostring(r) end
    return tip
end

T.test("lfg: on by default", function()
    stub.Load({ before = function() LW.world({})(); DaylightUIDB = nil end })
    T.truthy(stub.lfg.Window.frame, "built")
end)

T.test("lfg: switched off, the game's window stays the game's", function()
    local ns = load({ enabled = false })
    T.isnil(ns.Window.frame, "nothing built")
    LW.Toggle(1)
    frame(5)
    T.eq(LFGParentFrame:GetParent(), UIParent, "not parked")
    T.truthy(LFGParentFrame:IsVisible(), "the game's own window shows")
end)

T.test("lfg: the header's swap icon hands over to the game's window and it stays picked", function()
    stub.Load({ before = LW.world(), skins = true })
    local ns = stub.lfg
    local f = open(ns)
    T.truthy(DaylightUI.Win.IsOpen(f))
    T.truthy(f.swap and f.swap:IsShown(), "the swap icon sits in the header")
    T.isnil(stub.skins.Kit.ShellOf(LFGParentFrame), "the skins leave it alone while covered")
    T.truthy(f.swap:GetRight() == nil or f.gear:GetRight() == nil or f.swap:GetRight() <= f.gear:GetLeft(), "left of the gear")
    f.swap:Click()
    frame(10)
    T.eq(DaylightUI:Get("GroupFinder", "enabled"), false, "the pick is saved")
    T.falsy(DaylightUI.Win.IsOpen(f), "ours steps aside")
    T.eq(LFGParentFrame:GetParent(), UIParent, "the game's window is back")
    T.truthy(LFGParentFrame:IsVisible(), "and shows")
    T.eq(_G.LFGListingComment:GetParent(), LFGParentFrame.ListingFrame.ActivityView, "with its own note box")
    T.truthy(ns.Window.swap.link:IsShown(), "with its way back")
    T.falsy(ns.Window.Covers(), "the skins may dress it")
    stub.RunTimers()
    T.truthy(stub.skins.Kit.ShellOf(LFGParentFrame), "in the Daylight UI look")
    LW.Close()
    frame(10)
    T.eq(LFGParentFrame:GetParent(), UIParent, "never parked while it's the pick")
    LW.Toggle(1)
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f), "the key opens the game's window next time")
    T.truthy(LFGParentFrame:IsVisible())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("lfg: the game's window's link switches back to Daylight UI's, no reload", function()
    stub.Load({ before = LW.world({ enabled = false }), skins = true })
    local ns = stub.lfg
    LW.Toggle(2)
    frame(5)
    T.isnil(ns.Window.frame, "nothing built while the game's is picked")
    local b = ns.Window.swap.link
    T.truthy(b and b:IsShown(), "the game's window has the switch")
    T.eq(b:GetParent(), LFGParentFrame, "it rides on the game's window")
    b:Click()
    frame(20)
    T.eq(DaylightUI:Get("GroupFinder", "enabled"), true, "the pick is saved")
    local f = ns.Window.frame
    T.truthy(f and DaylightUI.Win.IsOpen(f), "ours opens in its place")
    T.eq(f.tab, "find", "on the page the game's showed")
    T.eq(LFGParentFrame:GetParent(), DaylightUI.Win.Followers.hidden, "the game's frame is parked")
    T.truthy(LFGParentFrame:IsShown(), "still open underneath, so its key closes both")
    T.falsy(b:IsVisible(), "the link is gone with the game's look")
    T.truthy(ns.Window.Covers())
    LW.Toggle()
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f), "the game's key closes ours")
    T.eq(#LW.Calls("Search"), 0, "switching never searches")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("lfg: the game's key opens ours in its place, on List yourself (the first tab), without searching", function()
    local ns = load()
    local f = open(ns)
    T.truthy(DaylightUI.Win.IsOpen(f), "ours open")
    T.eq(LFGParentFrame:GetParent(), DaylightUI.Win.Followers.hidden, "the game's frame is parked")
    T.eq(#f.tabs, 3)
    T.eq(f.tabs[1].id, "list", "List yourself first")
    T.eq(f.tab, "list")
    T.eq(f.title:GetText(), "Group Finder")
    T.eq(f.sub:GetText(), "Not listed")
    T.eq(#LW.Calls("Search"), 0, "a search needs a click or a key: opening never searches")
    stub.Key(function() ns.Window.Open("find") end)   -- not a tab click, so still no search
    frame(5)
    T.eq(#LW.Calls("Search"), 0)
    T.eq(ns.Browse.page.note:GetText(), "Pick a category to look for groups.")
    T.isnil(blocked(), tostring(blocked()))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("lfg: closing ours hides the game's; the game's key again closes ours", function()
    local ns = load()
    local f = open(ns)
    ns.Window.Close()
    frame(20)
    T.falsy(LFGParentFrame:IsShown(), "the game's frame hidden too")
    T.falsy(DaylightUI.Win.IsOpen(f))
    open(ns)
    T.truthy(DaylightUI.Win.IsOpen(f))
    LW.Toggle(1)   -- the key while open hides it
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f), "ours follows")
end)

T.test("lfg: the category chips list what's there at your level", function()
    local ns = load()
    open(ns)
    local chips = {}
    for _, b in ipairs(ns.Listing.page.catChips) do if b:IsShown() then chips[#chips + 1] = b.text:GetText() end end
    T.eq(table.concat(chips, ", "), "Dungeons, Quests & Zones, Custom", "Raids: nothing at level 14")
end)

T.test("lfg: the header's gear shows every level, as the game's finder's does", function()
    local ns = load()
    local f = open(ns)
    local W = DaylightUI.Widgets
    local was, keys, values, pick, opts = W.OpenMenu
    W.OpenMenu = function(_, k, v, _, onPick, _, o) keys, values, pick, opts = k, v, onPick, o end
    T.truthy(f.gear, "a gear left of the X")
    stub.Key(function() f.gear:GetScript("OnClick")(f.gear) end)
    W.OpenMenu = was
    T.eq(#keys, 1)
    T.eq(opts.checked(keys[1]), false, "off: the levels around yours")
    stub.Key(function() pick(keys[1]) end)
    frame(5)
    T.eq(opts.checked(keys[1]), true)
    local chips = {}
    for _, b in ipairs(ns.Listing.page.catChips) do if b:IsShown() then chips[#chips + 1] = b.text:GetText() end end
    T.truthy(table.concat(chips, ", "):find("Raids", 1, true), "Raids at level 14 once every level shows")
end)

T.test("lfg: Find a group's tab searches the dungeons at your level and lists groups, then solo players", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local s = LW.Calls("Search")[1]
    T.eq(s[1], 2, "Dungeons")
    T.eq(table.concat(s[2], ","), "798,799", "Scarlet Monastery is above your level")
    local list = rows(ns.Browse.page.stack, "group")
    T.eq(#list, 3)
    T.eq(texts(list), "Ragefire Chasm | Wailing Caverns | Ragefire Chasm", "the group first (alone), then solo players")
    T.truthy(list[2].sub:GetText():find("Sela", 1, true), "a solo player who can tank before one who can't")
    -- The group's five slots: filled when taken, rings when open.
    local open = 0
    for _, b in ipairs(list[1].badges) do if b:IsShown() and b.art:GetAlpha() < 1 then open = open + 1 end end
    T.eq(open, 2, "two damage places open")
    T.eq(list[1].age:GetText(), "just now")
    T.eq(list[3].age:GetText(), "20 min")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("lfg: a wide window puts groups and solo players side by side", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local stack = ns.Browse.page.stack
    local list = rows(stack, "group")
    for _, b in ipairs(list) do T.falsy(b.col, "one column at the window's own width") end
    -- The fake game has no layout: the list's width is given, as a grip drag would.
    stack.scroll.GetWidth = function() return ns.Browse.SPLIT_W + 40 end
    ns.Browse.Render(nil, true)
    list = rows(stack, "group")
    T.eq(#list, 3)
    T.eq(list[1].col, 1, "the group on the left")
    T.eq(list[2].col, 2, "solo players on the right")
    T.eq(list[3].col, 2)
    T.near(list[2].colY, list[1].colY, 0.5, "both lists start at the same height")
    local half = math.floor((stack:Width() - DaylightUI.Win.Parts.GAP) / 2)
    T.near(list[1]:GetWidth(), half, 0.5, "each half the list")
    T.near(stack.height, list[3].colY + list[3]:GetHeight(), 0.5, "the list as tall as its taller column")
    -- Mid-drag it switches as the list crosses the width, and only then refills.
    local renders, render = 0, ns.Browse.Render
    ns.Browse.Render = function(...) renders = renders + 1; return render(...) end
    stack.scroll.GetWidth = function() return ns.Browse.SPLIT_W + 60 end
    ns.Window.Resized(nil, nil, true)
    T.eq(renders, 0, "still wide: the rows only stretch")
    stack.scroll.GetWidth = function() return ns.Browse.SPLIT_W - 40 end
    ns.Window.Resized(nil, nil, true)
    T.eq(renders, 1, "narrow: one refill right away")
    T.falsy(rows(stack, "group")[2].col, "back to one column while still dragging")
    ns.Window.Resized(nil, nil, true)
    T.eq(renders, 1, "no more refills while it stays narrow")
    ns.Browse.Render = render
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("lfg: on a controller Y refreshes Find a group, the menu button opens the gear's options", function()
    local ns = load()
    local f = open(ns)
    tab(ns, "find")
    local function entry(key)
        for _, e in ipairs(f.padKeys) do
            if e.key == key and (not e.when or e.when()) then return e end
        end
    end
    local before = #LW.Calls("Search")
    stub.Key(function() entry("Y").run() end)
    T.eq(#LW.Calls("Search"), before + 1, "searched again")
    T.isnil(entry("X"), "no X on Find a group")
    entry("MENU_RIGHT").run()
    T.eq(DaylightUI.Widgets.menuOwner, f.gear, "the gear's menu, under the gear")
    DaylightUI.Widgets.CloseMenu()
    tab(ns, "list")
    T.isnil(entry("X"), "nothing ticked: nothing to list")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: picking Razorfen Kraul from All activities got "blocked UNKNOWN()"
-- from C_LFGList.Search under the menu click. The category's search already holds
-- every activity's groups, so a pick only narrows the list with no second search.
T.test("lfg: picking an activity narrows the list without searching again", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local before = #LW.Calls("Search")
    ns.Browse.page.act:Click()
    local wc
    for i = 1, 4 do
        local r = DaylightUI.Widgets.MenuRow(i)
        if r and r:IsShown() and r.text:GetText() == "Wailing Caverns" then wc = r end
    end
    T.truthy(wc, "Wailing Caverns in the menu")
    wc:Click()
    T.eq(#LW.Calls("Search"), before, "no second search")
    T.eq(texts(rows(ns.Browse.page.stack, "group")), "Wailing Caverns")
    T.eq(ns.Browse.page.act.text:GetText(), "Wailing Caverns")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game in French: "Champs de bataille" and "Personnalisé" ran past the
-- window's edge. Long names wrap to a second row and the activity button and
-- list move down under them.
T.test("lfg: long category names wrap inside the window", function()
    local names = {}
    for id, c in pairs(LW.CATEGORIES) do names[id] = c.name end
    LW.CATEGORIES[2].name, LW.CATEGORIES[116].name = "Donjons", "Champs de bataille et zones"
    LW.CATEGORIES[120].name = "Personnalisé"
    local ok, err = pcall(function()
        local ns = load()
        open(ns)
        tab(ns, "find")
        local page = ns.Browse.page
        local right, bottom = ns.Browse.Width(page) - ns.Browse.EDGE, 0
        for _, b in ipairs(page.chips) do
            if b:IsShown() then
                local _, _, _, x, y = b:GetPoint(1)
                T.truthy(x + b:GetWidth() <= right, b.text:GetText() .. " ends at " .. (x + b:GetWidth()) .. " of " .. right)
                bottom = math.max(bottom, -y + b:GetHeight())
            end
        end
        local _, _, _, _, ay = page.act:GetPoint(1)
        T.truthy(-ay > bottom, "the activity button under the last row")
        local sy
        for n = 1, page.stack.scroll:GetNumPoints() do
            local p, _, _, _, py = page.stack.scroll:GetPoint(n)
            if p == "TOPLEFT" then sy = py end
        end
        T.truthy(-sy >= -ay + page.act:GetHeight(), "the list under the activity button")
    end)
    for id, n in pairs(names) do LW.CATEGORIES[id].name = n end
    if not ok then error(err, 0) end
end)

T.test("lfg: hovering a group shows the whole party", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local tip = recordTips()
    local row = rows(ns.Browse.page.stack, "group")[1]
    row:GetScript("OnEnter")(row)
    local text = table.concat(tip.lines, "\n")
    T.truthy(text:find("Ragefire Chasm", 1, true), text)
    T.truthy(text:find("Gorrak Stonefist", 1, true) and text:find("Mira Dawnsong", 1, true) and text:find("Tuk", 1, true), text)
    T.truthy(text:find("need dps", 1, true), "the leader's note")
    T.truthy(text:find("Open spot", 1, true), "the places still open")
    T.truthy(text:find("Relaxed", 1, true), "its playstyle")
    T.truthy(row.sub:GetText():find("Relaxed", 1, true), "on the row too, at a glance")
end)

T.test("lfg: the leader's zone shows on the row, the tooltip and the card", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local tip = recordTips()
    local list = rows(ns.Browse.page.stack, "group")
    local row, solo = list[1], list[2]
    T.truthy(row.sub:GetText():find("Westfall", 1, true), row.sub:GetText())
    T.truthy(solo.sub:GetText():find("The Barrens", 1, true), "a player listed alone is their own leader: " .. solo.sub:GetText())
    row:GetScript("OnEnter")(row)
    T.truthy(table.concat(tip.lines, "\n"):find("Zone = Westfall", 1, true), "in the tooltip")
    T.falsy(ns.Browse.results[3].leader.zone, "no zone from the client: no word for it")
    ns.Browse.Toggle(ns.Browse.results[1].id)
    frame(20)
    local lines = card(ns.Browse.page.detail)
    T.eq(lines.Zone, "Westfall", "the leader's zone on the card")
    T.falsy(lines["In the group"]:find("Westfall", 1, true), "the zone is the leader's alone")
end)

T.test("lfg: the sub line colors level, zone and playstyle; the note has its own line", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local Style, Hex = DaylightUI.Style, DaylightUI.Win.Parts.Hex
    local list = rows(ns.Browse.page.stack, "group")
    local row, quiet = list[1], list[3]
    local sub = row.sub:GetText()
    T.truthy(sub:find(Hex({ Style.Accent() }) .. "15|r", 1, true), "the level pops: " .. sub)
    T.truthy(sub:find(Hex(Style.INK.WARN) .. "Westfall|r", 1, true), "the zone: " .. sub)
    T.truthy(sub:find(Hex(Style.INK.GOOD) .. "Relaxed|r", 1, true), "the playstyle: " .. sub)
    T.falsy(sub:find("need dps", 1, true), "the note left the sub line")
    T.eq(row.note:GetText(), "need dps")
    T.truthy(row.note:IsShown())
    T.eq(row:GetHeight(), ns.Rows.GROUP_NOTE, "a note makes the row taller")
    T.falsy(quiet.note:IsShown(), "no note, no line")
    T.eq(quiet:GetHeight(), ns.Rows.GROUP)
    T.eq(ns.Data.PlaystyleInk(1), Style.INK.GOOD)
    T.eq(ns.Data.PlaystyleInk(3), Style.INK.DAMAGE)
    T.eq(ns.Data.PlaystyleInk(4), Style.INK.MONEY)
    T.eq(ns.Data.PlaystyleInk(nil), nil)
end)

T.test("lfg: a secret or empty zone is left out", function()
    local ns = load()
    local real = C_LFGList.GetSearchResultPlayerInfo
    for _, z in ipairs({ stub.Secret("Westfall"), "" }) do
        C_LFGList.GetSearchResultPlayerInfo = function(id, i)
            local m = real(id, i)
            if m then m.areaName = z end
            return m
        end
        T.falsy(ns.Data.Result(17).leader.zone)
    end
    C_LFGList.GetSearchResultPlayerInfo = real
end)

T.test("lfg: the client refuses a new listing without a playstyle (never sent by ours)", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    local L = ns.Listing
    local acts = rows(L.page.stack, "act")
    acts[1]:GetScript("OnClick")(acts[1], "LeftButton")
    stub.Key(L.Post)
    T.eq(#LW.Calls("CreateListing"), 0, "List me waits for a playstyle")
    T.isnil(ns.Data.Entry())
end)

-- Seen in game: right after List me the server's search can come back without the
-- listing just made, so Find showed everyone but you until Refresh. Your own listing
-- is known without asking the server, so it shows at once, once.
local function mineRows(ns)
    local out = {}
    for _, b in ipairs(rows(ns.Browse.page.stack, "group")) do
        if b.spec.result and b.spec.result.mine then out[#out + 1] = b end
    end
    return out
end

T.test("lfg: a new listing shows on Find even when the game's search missed it", function()
    local ns = load({ lag = true })
    open(ns)
    tab(ns, "list")
    local L = ns.Listing
    local acts = rows(L.page.stack, "act")
    local listed = acts[1].name:GetText()
    acts[1]:GetScript("OnClick")(acts[1], "LeftButton")
    L.PickStyle(2)
    stub.Key(L.Post)
    frame(20)
    T.eq(ns.Window.page, "find", "the window went to Find a group")
    local mine = mineRows(ns)
    T.eq(#mine, 1, "your listing is on the list without a Refresh")
    T.truthy(mine[1].spec.text:find(listed, 1, true), "it names the activity you listed")
    T.truthy(mine[1].spec.sub:find(DaylightUI.UnitName("player"), 1, true), "it names you")
    T.truthy(mine[1].spec.sub:find("Barrens", 1, true), "and where you are")
    -- Its card still offers Edit and Unlist.
    click(mine[1])
    frame(20)
    local _, buttons = card(ns.Browse.page.detail)
    T.eq(table.concat(buttons, ","), "Edit listing,Unlist", "the card offers Edit and Unlist")
    -- The server catches up: a Refresh brings the real one, never two.
    LW.state.lag = false
    tab(ns, "list")
    stub.Key(L.Post)   -- an update puts it in the server's results
    frame(20)
    tab(ns, "find")
    stub.Key(function() ns.Browse.page.refresh:GetScript("OnClick")(ns.Browse.page.refresh) end)
    frame(20)
    T.eq(#mineRows(ns), 1, "one row for your listing after the real one arrives")
    -- Unlisted: gone at once.
    stub.Key(L.Unlist)
    frame(20)
    T.eq(#mineRows(ns), 0, "no row once you unlist")
end)

T.test("lfg: a new listing shows on Find even when the game's search never answers", function()
    local ns = load({ lag = true })
    open(ns)
    tab(ns, "list")
    local L = ns.Listing
    local acts = rows(L.page.stack, "act")
    acts[1]:GetScript("OnClick")(acts[1], "LeftButton")
    L.PickStyle(1)
    local fire = stub.FireEvent
    stub.FireEvent = function(e, ...) if e ~= "LFG_LIST_SEARCH_RESULTS_RECEIVED" then return fire(e, ...) end end
    stub.Key(L.Post)
    frame(20)
    stub.FireEvent = fire
    stub.Advance(ns.Browse.WAIT + 1)
    frame(5)
    T.falsy(ns.Browse.searching, "gave up waiting")
    T.eq(#mineRows(ns), 1, "your listing shows anyway")
end)

-- After a new listing the game searches only that listing's activities, and an
-- addon can't search without a click. Find says so, and one click on its button
-- shows every group of the category. In game it showed "All activities" over only
-- three Stockades groups.
local function listedIDs(ns) return table.concat(ns.Data.Entry().activityIDs, ",") end

T.test("lfg: after listing, Find names what was searched; Refresh keeps it, Show all searches the whole category", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    local L = ns.Listing
    local acts = rows(L.page.stack, "act")
    local listed = acts[1].name:GetText()
    acts[1]:GetScript("OnClick")(acts[1], "LeftButton")
    L.PickStyle(1)
    stub.Key(L.Post)
    frame(20)
    local B = ns.Browse
    T.eq(#LW.Calls("GameSearch"), 1, "the game searched your listing's activity")
    T.eq(B.page.act.text:GetText(), listed, "the activity button names what was searched, not All activities")
    T.eq(B.page.refresh.text:GetText(), "Refresh", "Refresh never changes its meaning")
    T.truthy(B.page.all:IsShown(), "Show all, its own button, while the list is narrowed")
    T.eq(B.page.all.text:GetText(), "Show all")
    local before = #rows(B.page.stack, "group")
    stub.Key(function() B.page.refresh:GetScript("OnClick")(B.page.refresh) end)
    frame(20)
    local s = LW.Calls("Search")
    T.eq(table.concat(s[#s][2], ","), listedIDs(ns), "Refresh searches what's shown again")
    T.eq(B.page.act.text:GetText(), listed, "still narrowed")
    T.truthy(B.page.all:IsShown())
    stub.Key(function() B.page.all:GetScript("OnClick")(B.page.all) end)
    frame(20)
    s = LW.Calls("Search")
    T.eq(#s[#s][2], #ns.Data.Filtered(2), "every activity of the category")
    T.eq(B.page.act.text:GetText(), "All activities")
    T.falsy(B.page.all:IsShown(), "Show all fades away once everything shows")
    T.truthy(#rows(B.page.stack, "group") > before, "the other groups show")
end)

-- Unlisting from your own opened row on Find removes the row at once, without
-- needing Refresh.
T.test("lfg: unlisting from Find takes your row away at once", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    local L = ns.Listing
    local acts = rows(L.page.stack, "act")
    acts[1]:GetScript("OnClick")(acts[1], "LeftButton")
    L.PickStyle(1)
    stub.Key(L.Post)
    frame(20)
    local B = ns.Browse
    local function mine()
        for _, b in ipairs(rows(B.page.stack, "group")) do if b.spec.result.mine then return b end end
    end
    T.truthy(mine(), "your listing shows")
    B.Toggle(99)
    frame(20)
    local _, buttons = card(B.page.detail)
    T.eq(buttons[2], "Unlist")
    local b = B.page.detail.buttons[2]
    b:GetScript("OnClick")(b)
    frame(20)
    T.eq(#LW.Calls("RemoveListing"), 1)
    T.isnil(mine(), "your row is gone without a Refresh")
    T.isnil(B.open, "nothing of yours left open")
end)

T.test("lfg: a click opens the group's card beside the list: Whisper the leader, no Invite for a group", function()
    local ns = load()
    local f = open(ns)
    tab(ns, "find")
    local row = rows(ns.Browse.page.stack, "group")[1]
    local narrow = f:GetWidth()
    click(row)
    T.eq(ns.Browse.open, 17)
    local d = ns.Browse.page.detail
    T.truthy(d:IsOpen() and d.frame:IsShown(), "opened")
    T.near(f:GetWidth(), narrow + ns.Window.Span(), 0.5, "the window made room for it")
    local lines, buttons = card(d)
    T.eq(d.frame.title:GetText(), "Gorrak Stonefist")
    T.truthy(lines.Activity and lines.Activity:find("Deadmines", 1, true) or lines.Activity, "the activity")
    T.truthy(lines["In the group"]:find("Mira Dawnsong", 1, true), "who is in")
    T.truthy(lines["In the group"]:find("Open spot", 1, true), "what is still open")
    T.eq(lines.Playstyle, "Relaxed")
    T.truthy(lines.Note and lines.Note:find("need dps", 1, true), "the leader's note")
    T.eq(table.concat(buttons, ","), "Whisper", "only a player listed alone can be invited: no Invite here")
    local asked = whispers()
    d.buttons[1]:GetScript("OnClick")(d.buttons[1])
    T.eq(asked[1], "Whisper Gorrak Stonefist", "Daylight UI's own box asks for the words")
    T.eq(#LW.Calls("SendTell"), 0, "the game's chat box is never opened from here")
    T.truthy(row.pick:IsShown(), "the row is the picked one")
    -- Clicked again: the card closes and the window goes back.
    click(row)
    T.isnil(ns.Browse.open)
    T.falsy(d:IsOpen())
    T.near(f:GetWidth(), narrow, 0.5, "the room is given back")
    T.falsy(row.pick:IsShown())
end)

-- With one group picked, clicking another moves the card to it.
T.test("lfg: another group clicked takes the card, a refill midway or not", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local list = rows(ns.Browse.page.stack, "group")
    click(list[1])
    T.eq(ns.Browse.open, 17)
    list = rows(ns.Browse.page.stack, "group")
    click(list[2])
    LW.Update(17, {})
    frame(20)
    T.truthy(ns.Browse.open and ns.Browse.open ~= 17, "the second one picked")
    local d = ns.Browse.page.detail
    T.truthy(d:IsOpen(), "still one card")
    T.eq(d.frame.title:GetText(), ns.Browse.shown[ns.Browse.open].leader.name)
    local picked = 0
    for _, b in ipairs(rows(ns.Browse.page.stack, "group")) do if b.pick:IsShown() then picked = picked + 1 end end
    T.eq(picked, 1, "one row picked")
end)

T.test("lfg: a player listed alone can be invited", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local solo = rows(ns.Browse.page.stack, "group")[3]
    click(solo)
    local d = ns.Browse.page.detail
    local lines, buttons = card(d)
    T.eq(table.concat(buttons, ","), "Invite,Whisper")
    T.truthy(lines["Can be"], "the roles they can fill")
    d.buttons[1]:GetScript("OnClick")(d.buttons[1])
    T.eq(LW.Calls("InviteUnit")[1][1], "Ularanu Seachaser")
end)

T.test("lfg: Who offers Invite only when it can work", function()
    local ns = load()
    open(ns)
    tab(ns, "who")
    local d = ns.Who.page.detail
    local function buttons() local _, b = card(d); return table.concat(b, ",") end
    click(rows(ns.Who.page.stack, "person")[1])
    T.eq(buttons(), "Whisper,Invite", "alone: you may invite")
    LW.Group(3, false)
    frame(2)
    T.eq(buttons(), "Whisper", "joining a group you don't lead: the open card drops Invite at once")
    LW.Group(3, true)
    frame(2)
    T.eq(buttons(), "Whisper,Invite", "made leader: Invite again")
end)

T.test("lfg: List yourself lends the game's note box into ours and gives it back", function()
    local ns = load()
    local f = open(ns)
    tab(ns, "list")
    local page = ns.Listing.page
    T.eq(LFGListingComment:GetParent(), page.noteBox, "the game's box sits in ours")
    local roles = {}
    for _, b in ipairs(page.roleChips) do if b:IsShown() then roles[#roles + 1] = b.text:GetText() end end
    T.eq(#roles, 3, "any role, whatever the class or spec: the game's page offers all three")
    -- Compact enough to show many dungeons: labels beside their rows, a one-line
    -- note, the category as the list's heading.
    local oy
    for n = 1, page.stack.scroll:GetNumPoints() do
        local p, _, _, _, py = page.stack.scroll:GetPoint(n)
        if p == "TOPLEFT" then oy = py end
    end
    T.truthy(-oy <= 210, "the activities start high: " .. tostring(-oy))
    T.eq(page.rolesHead:GetText(), "Roles")
    local _, _, _, rx = page.roleChips[1]:GetPoint(1)
    T.eq(rx, ns.Listing.EDGE + ns.Listing.IN + ns.Listing.LABEL_W, "the buttons beside their label")
    ns.Window.Close()
    frame(20)
    T.eq(LFGListingComment:GetParent(), LFGListingFrame.ActivityView, "given back")
    T.falsy(DaylightUI.Win.IsOpen(f))
end)

T.test("lfg: tick an activity, write a note, List me: listed, and Find a group shows yours first", function()
    local ns = load()
    local f = open(ns)
    tab(ns, "list")
    local L = ns.Listing
    T.truthy(L.page.foot.buttons[1].spec.off, "nothing ticked: List me waits")
    local acts = rows(L.page.stack, "act")
    T.eq(texts(acts), "Wailing Caverns | Ragefire Chasm", "lowest level first (12-25, 13-18)")
    acts[2]:GetScript("OnClick")(acts[2], "LeftButton")
    LW.Type("hello")
    frame(2)
    T.truthy(L.page.foot.buttons[1].spec.off, "no playstyle yet")
    T.eq(L.page.why:GetText(), "Select Playstyle (required)", "the game's words")
    local styles = {}
    for _, b in ipairs(L.page.styleChips) do if b:IsShown() then styles[#styles + 1] = b.text:GetText() end end
    T.eq(table.concat(styles, ", "), "Learning, Relaxed, Competitive, Carry Offered")
    L.page.styleChips[3]:GetScript("OnClick")(L.page.styleChips[3])
    T.truthy(L.page.styleChips[3].active, "picked")
    T.falsy(L.page.foot.buttons[1].spec.off, "something ticked, a playstyle picked")
    T.eq(L.page.foot.buttons[1].text:GetText(), "List me")
    stub.Key(function() L.page.foot.buttons[1]:GetScript("OnClick")(L.page.foot.buttons[1]) end)
    local made = LW.Calls("CreateListing")[1][1]
    T.eq(table.concat(made.activityIDs, ","), "798")
    T.eq(made.generalPlaystyle, 3, "Competitive goes with it")
    T.eq(LW.Calls("SetRoles")[1][1].dps, true, "your roles saved with it")
    frame(20)
    T.eq(f.tab, "find", "the window goes to Find a group")
    T.truthy(f.sub:GetText():find("Ragefire Chasm", 1, true), "the header says what you're listed for")
    local list = rows(ns.Browse.page.stack, "group")
    T.truthy(list[1].name:GetText():find("Your listing", 1, true), "yours first")
    T.eq(ns.Data.Entry().comment, "hello", "the note came from the game's box")
    T.isnil(blocked(), tostring(blocked()))
end)

T.test("lfg: List yourself sorts activities by level or A to Z, and keeps the pick", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    local L = ns.Listing
    T.eq(texts(rows(L.page.stack, "act")), "Wailing Caverns | Ragefire Chasm", "by level at first")
    T.eq(L.page.sort.text:GetText(), "Sort: Level")
    T.truthy(L.page.sort:IsShown(), "the button beside the categories")
    local _, _, _, _, sortTop = L.page.sort:GetPoint(1)
    local _, _, _, _, chipTop = L.page.catChips[1]:GetPoint(1)
    T.eq(sortTop, chipTop, "level with the category buttons")
    local openMenu, opened = DaylightUI.Widgets.OpenMenu, false
    DaylightUI.Widgets.OpenMenu = function() opened = true end
    L.page.sort:GetScript("OnClick")(L.page.sort)
    DaylightUI.Widgets.OpenMenu = openMenu
    T.falsy(opened, "two orders: a click flips, no menu")
    frame(5)
    T.eq(DaylightUI:Get("GroupFinder", "activitySort"), "name", "saved")
    T.eq(texts(rows(L.page.stack, "act")), "Ragefire Chasm | Wailing Caverns", "A to Z")
    T.eq(L.page.sort.text:GetText(), "Sort: Name")
    -- Find's activity menu follows the same order.
    T.eq(ns.Data.Groups(2)[1].acts[1].name, "Ragefire Chasm")
    L.page.sort:GetScript("OnClick")(L.page.sort)
    frame(5)
    T.eq(DaylightUI:Get("GroupFinder", "activitySort"), "level", "a second click flips back")
    T.eq(L.page.sort.text:GetText(), "Sort: Level")
end)

T.test("lfg: listed, the page offers Update and Unlist", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    local L = ns.Listing
    local acts = rows(L.page.stack, "act")
    acts[1]:GetScript("OnClick")(acts[1], "LeftButton")
    L.PickStyle(1)
    stub.Key(L.Post)
    frame(20)
    L.style = nil   -- a new session, so the page reads it back from your listing
    tab(ns, "list")
    T.truthy(ns.Window.frame.sub:GetText():find("Listed", 1, true), "the header says you're listed")
    T.eq(L.style, 1, "your listing's playstyle")
    T.eq(L.page.foot.buttons[1].text:GetText(), "Update")
    T.truthy(L.page.foot.buttons[1].spec.off, "nothing changed yet")
    acts = rows(L.page.stack, "act")
    acts[2]:GetScript("OnClick")(acts[2], "LeftButton")
    T.falsy(L.page.foot.buttons[1].spec.off, "a change")
    local kits, wasKit, wasPlay = {}, _G.SOUNDKIT, _G.PlaySound
    _G.SOUNDKIT = { PVP_ENTER_QUEUE = 8458, LFG_DENIED = 17341 }
    _G.PlaySound = function(kit) kits[#kits + 1] = kit end
    stub.Key(L.Post)
    T.eq(table.concat(LW.Calls("UpdateListing")[1][1].activityIDs, ","), "798,799")
    T.eq(LW.Calls("UpdateListing")[1][1].generalPlaystyle, 1, "kept on an update")
    frame(20)
    T.deq(kits, { 8458 }, "the game's sound for an update: only its own button plays it")
    L.PickStyle(4)
    T.falsy(L.page.foot.buttons[1].spec.off, "another playstyle is a change")
    frame(20)
    T.eq(L.page.foot.buttons[2].text:GetText(), "Unlist")
    L.page.foot.buttons[2]:GetScript("OnClick")(L.page.foot.buttons[2])
    frame(20)
    _G.SOUNDKIT, _G.PlaySound = wasKit, wasPlay
    T.eq(#LW.Calls("RemoveListing"), 1)
    T.deq(kits, { 8458, 17341 }, "and for taking it down")
    T.eq(ns.Window.frame.sub:GetText(), "Not listed")
end)

T.test("lfg: in a group you don't lead, the listing is the leader's", function()
    local ns = load()
    open(ns)
    LW.Group(3, false)
    tab(ns, "list")
    local L = ns.Listing
    T.truthy(L.page.locked:IsShown())
    T.truthy(L.page.foot.buttons[1].spec.off)
    T.truthy(L.page.rolesHead:IsShown(), "your own role is yours to pick, leader or not")
end)

-- The game's solo role buttons (Blizzard_LFGVanilla_Listing.xml). Each toggles on
-- its own, all three for every class. A role not recommended only looks dimmed.
T.test("lfg: alone you list as several roles, any you like", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    local page = ns.Listing.page
    local function click(i) page.roleChips[i]:GetScript("OnClick")(page.roleChips[i]) end
    T.truthy(page.roleChips[3].active, "damage, as saved")
    T.truthy(page.roleChips[1]:IsShown(), "tank shows though your spec isn't one")
    click(1)
    T.truthy(page.roleChips[1].active, "tank, though a shaman isn't advised to")
    T.truthy(page.roleChips[3].active, "damage stays on")
    T.deq(C_LFGListRoles.GetRoles(), { tank = true, healer = false, dps = true }, "the game has both")
    click(3)
    click(1)
    T.falsy(page.roleChips[3].active)
    T.truthy(page.roleChips[1].active, "never the last one off")
end)

T.test("lfg: a role the game won't take goes back off", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    local page = ns.Listing.page
    LW.state.rolesRefused = true
    page.roleChips[2]:GetScript("OnClick")(page.roleChips[2])
    frame(2)
    T.falsy(page.roleChips[2].active, "the game's own revert")
    T.truthy(page.roleChips[3].active)
end)

T.test("lfg: alone in an instance group, the solo roles stay", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    local page = ns.Listing.page
    LW.state.instanceGroup = true
    page.roleChips[2]:GetScript("OnClick")(page.roleChips[2])
    T.truthy(page.roleChips[2].active)
    T.truthy(page.roleChips[3].active)
    T.eq(#LW.Calls("UnitSetRole"), 0)
end)

-- The game's listing page (LFGListingRoleDropdown_SetupDropdown). In a group your
-- role is a single pick through UnitGroupRolesAssigned / UnitSetRole, not the solo three.
T.test("lfg: in a group you pick your one role, leader or not", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    LW.Group(3, true)
    frame(2)
    local L = ns.Listing
    local page = L.page
    T.truthy(page.rolesHead:IsShown(), "the leader has the role row")
    T.truthy(page.roleChips[1]:IsShown(), "tank too: the game's menu has all three")
    T.truthy(page.roleChips[2]:IsShown(), "healer")
    T.truthy(page.roleChips[3]:IsShown(), "damage")
    T.falsy(page.roleChips[2].active, "no role yet: nothing lit, though alone you ticked damage")
    T.falsy(page.roleChips[3].active, "no role yet: nothing lit, though alone you ticked damage")
    stub.Key(function() page.roleChips[2]:GetScript("OnClick")(page.roleChips[2]) end)
    frame(2)
    T.eq(LW.Calls("UnitSetRole")[1][2], "HEALER")
    T.truthy(page.roleChips[2].active, "healer lit once the game says so")
    stub.Key(function() page.roleChips[3]:GetScript("OnClick")(page.roleChips[3]) end)
    frame(2)
    T.falsy(page.roleChips[2].active, "one role: healer went off")
    T.truthy(page.roleChips[3].active)
    T.eq(#LW.Calls("SetRoles"), 0, "your solo roles stay as you left them")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "; "))
end)

-- Listed alone as a tank, you invite someone: the client makes everyone Damage as the
-- group forms, and the tank who listed came out as Damage.
T.test("lfg: listed as a tank, inviting someone keeps you the tank", function()
    load()
    LW.state.roles = { tank = true, healer = false, dps = false }
    LW.state.entry = { activityIDs = { 1 } }
    stub.FireEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    LW.Group(2, true)
    LW.ClientRole("DAMAGER")
    T.eq(LW.state.role, "TANK", "the role you listed with, not the client's Damage")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "; "))
end)

T.test("lfg: the group role is left alone when it's one you listed, or one you pick", function()
    local ns = load()
    LW.state.roles = { tank = true, healer = false, dps = true }
    LW.state.entry = { activityIDs = { 1 } }
    stub.FireEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    LW.Group(2, true)
    LW.ClientRole("DAMAGER")
    T.eq(LW.state.role, "DAMAGER", "Damage was one of yours")
    LW.ClientRole("HEALER")
    T.eq(LW.state.role, "TANK", "a role you didn't list goes back to one you did")
    stub.Key(function() ns.Listing.ToggleRole("HEALER") end)
    LW.ClientRole("HEALER")
    T.eq(LW.state.role, "HEALER", "your own pick stays")
end)

T.test("lfg: not listed, the client's group role stays; in a fight it waits", function()
    load()
    LW.state.roles = { tank = true, healer = false, dps = false }
    LW.Group(2, true)
    LW.ClientRole("DAMAGER")
    T.eq(#LW.Calls("UnitSetRole"), 0, "nothing listed: nothing to keep")
    LW.Group(1, true)
    LW.state.entry = { activityIDs = { 1 } }
    stub.FireEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    stub.EnterCombat()
    LW.Group(2, true)
    LW.ClientRole("DAMAGER")
    T.eq(LW.state.role, "DAMAGER", "not in a fight")
    stub.LeaveCombat()
    T.eq(LW.state.role, "TANK", "right after it")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "; "))
end)

T.test("lfg: handed the lead with the page open, the list makes room and wakes", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    LW.Group(3, false)
    frame(2)
    local L = ns.Listing
    local function listTop()
        for n = 1, L.page.stack.scroll:GetNumPoints() do
            local p, _, _, _, y = L.page.stack.scroll:GetPoint(n)
            if p == "TOPLEFT" then return -y end
        end
    end
    local was = listTop()
    T.truthy(L.page.stack.used[1].spec.dim, "not yours to tick yet")
    LW.Group(3, true)
    stub.FireEvent("PARTY_LEADER_CHANGED")
    frame(2)
    T.truthy(L.page.styleChips[1]:IsShown(), "the playstyle row came")
    T.truthy(listTop() > was, "the list moved down under it")
    T.falsy(L.page.stack.used[1].spec.dim, "yours to tick now")
end)

T.test("lfg: Custom picks every activity and needs a note", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    local L = ns.Listing
    L.PickCat(120)
    L.PickStyle(2)
    T.truthy(L.page.note:IsShown())
    T.truthy(L.page.foot.buttons[1].spec.off, "no note yet")
    T.truthy(L.page.why:GetText():find("note", 1, true), L.page.why:GetText())
    LW.Type("questing buddies")
    frame(2)
    T.falsy(L.page.foot.buttons[1].spec.off)
end)

T.test("lfg: Who asks who's your level and lists them; Whisper the one picked", function()
    local ns = load()
    open(ns)
    tab(ns, "who")
    T.eq(LW.Calls("SendWho")[1][1], "14")
    T.eq(LW.Calls("SetWhoToUi")[1][1], true, "the answers to our page while it shows")
    local list = rows(ns.Who.page.stack, "person")
    T.eq(#list, 2)
    T.truthy(list[2].name:GetText():find("Stormcallers", 1, true), "the guild")
    T.eq(list[2].value:GetText(), "Boulder Lode Mine")
    local d = ns.Who.page.detail
    T.falsy(d:IsOpen(), "no one picked: no card")
    local narrow = ns.Window.frame:GetWidth()
    click(list[1])
    T.truthy(d:IsOpen(), "a card for the one picked")
    T.near(ns.Window.frame:GetWidth(), narrow + ns.Window.Span(), 0.5)
    local lines, buttons = card(d)
    T.eq(d.frame.title:GetText(), "Daemon Process")
    T.eq(lines.Level, "14")
    T.eq(lines.Race, "Orc")
    T.eq(lines.Zone, "Agama'gor")
    T.falsy(lines.Guild, "no guild, no line for it")
    T.eq(table.concat(buttons, ","), "Whisper,Invite")
    local asked = whispers()
    d.buttons[1]:GetScript("OnClick")(d.buttons[1])
    T.eq(asked[1], "Whisper Daemon Process")
    T.eq(#LW.Calls("SendTell"), 0, "the game's chat box is never opened from here")
    list = rows(ns.Who.page.stack, "person")
    click(list[2])
    T.eq(d.frame.title:GetText(), "Lava Flows")
    T.eq(card(d).Guild, "Stormcallers")
    click(rows(ns.Who.page.stack, "person")[2])
    T.falsy(d:IsOpen(), "picked again: the card closes")
    T.near(ns.Window.frame:GetWidth(), narrow, 0.5)
    ns.Window.Close()
    frame(20)
    local calls = LW.Calls("SetWhoToUi")
    T.eq(calls[#calls][1], false, "given back to the game as ours closes")
end)

T.test("lfg: in a fight ours opens, lends the note box and closes the game's with it", function()
    local ns = load()
    local f = open(ns)
    ns.Window.Close()
    frame(20)
    stub.EnterCombat()
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.eq(LFGParentFrame:GetParent(), DaylightUI.Win.Followers.hidden, "still parked: never the game's window")
    open(ns)
    T.truthy(DaylightUI.Win.IsOpen(f), "ours in the fight")
    T.eq(f.tab, "list")
    T.eq(LFGListingComment:GetParent(), ns.Listing.page.noteBox, "the note box lent in combat too")
    ns.Window.Close()
    frame(20)
    T.falsy(LFGParentFrame:IsShown(), "the game's frame closed in the fight")
    T.eq(LFGListingComment:GetParent(), LFGListingFrame.ActivityView, "the note box given back")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("lfg: motion off, everything still lands", function()
    local ns = load()
    DaylightUI:Set("general", "motion", false)
    open(ns)
    tab(ns, "find")
    local f = ns.Window.frame
    local narrow = f:GetWidth()
    local row = rows(ns.Browse.page.stack, "group")[1]
    stub.Key(function() row:GetScript("OnClick")(row, "LeftButton") end)
    T.truthy(ns.Browse.page.detail:IsOpen())
    T.near(f:GetWidth(), narrow + ns.Window.Span(), 0.5)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("lfg: the corner grip resizes the window: more room, the text its size", function()
    local ns = load()
    ns.Window.SaveSpot(600, 700)   -- dragged there earlier by the header
    local f = open(ns)
    local Win = DaylightUI.Win
    local grip = f.grip
    T.truthy(grip, "the window has a grip")
    -- The fake game has no layout, so edges come from the window's one anchor.
    f.GetLeft = function(self)
        local p, _, _, x = self:GetPoint(1)
        return p == "TOP" and x - self:GetWidth() / 2 or x
    end
    f.GetTop = function(self) return select(5, self:GetPoint(1)) end
    local scale = f:GetScale()
    local e = f:GetEffectiveScale()
    local function at(px, py) stub.cursorPos = { px * e, py * e } end
    local left, top = f:GetLeft(), f:GetTop()
    local cx, cy = left + f:GetWidth(), top - f:GetHeight()
    at(cx, cy)
    grip:GetScript("OnMouseDown")(grip, "LeftButton")
    at(cx + 140, cy - 100)
    stub.RunOnUpdate(grip, 1 / 30)
    T.near(f:GetWidth(), ns.Window.W + 140, 0.5, "wider as the corner goes right")
    T.near(f:GetHeight(), ns.Window.H + 100, 0.5, "taller as it goes down")
    T.near(f:GetLeft(), left, 0.01, "the top-left stays (x)")
    T.near(f:GetTop(), top, 0.01, "the top-left stays (y)")
    T.near(f:GetScale(), scale, 1e-6, "the text keeps its size")
    -- Mid-drag the rows follow the edge each frame without being refilled.
    local stack = f.pages[f.current].stack
    local renders, render = 0, ns.Browse.Render
    ns.Browse.Render = function(...) renders = renders + 1; return render(...) end
    local lr = ns.Listing.Render
    ns.Listing.Render = function(...) renders = renders + 1; return lr(...) end
    at(cx + 150, cy - 100)
    stub.RunOnUpdate(grip, 1 / 30)
    T.eq(renders, 0, "no fill mid-drag")
    T.truthy(#stack.pieces > 0, "the page has rows")
    for _, b in ipairs(stack.pieces) do
        if not b.col then T.near(b:GetWidth(), stack:Width(), 0.5, "a row as wide as the list now") end
    end
    ns.Browse.Render, ns.Listing.Render = render, lr
    at(cx - 500, cy + 500)
    stub.RunOnUpdate(grip, 1 / 30)
    T.near(f:GetWidth(), ns.Window.W, 0.5, "never narrower than it was made")
    T.near(f:GetHeight(), ns.Window.MIN_H, 0.5, "nor shorter than its least")
    at(cx + 60, cy - 40)
    grip:GetScript("OnMouseUp")(grip, "LeftButton")
    local size = ns.module.db.sizes.all
    T.near(size[1], ns.Window.W + 60, 0.5, "the width saved as the drag ends")
    T.near(size[2], ns.Window.H + 40, 0.5, "the height too")
    T.truthy(ns.module.db.spot, "its spot is saved too")
    -- Closed and reopened, it keeps its size.
    LW.Toggle(1); frame(20)
    LW.Toggle(1); frame(20)
    T.near(f:GetWidth(), ns.Window.W + 60, 0.5, "opens at the saved width")
    -- Right-click on the header resets the size.
    ns.Window.ResetSpot()
    frame(20)
    T.near(f:GetWidth(), ns.Window.W, 0.5, "reset: its own width again")
    T.falsy(ns.module.db.sizes, "and the size forgotten")
end)

T.test("lfg: the card is as wide as Social's, and the members each get their own line", function()
    local ns = load()
    local f = open(ns)
    tab(ns, "find")
    local narrow = f:GetWidth()
    click(rows(ns.Browse.page.stack, "group")[1])
    local d = ns.Browse.page.detail
    T.eq(d.frame:GetWidth(), DaylightUI.Social.Detail.W)
    T.eq(f:GetWidth(), narrow + DaylightUI.Social.Detail.SPAN)
    -- Each person is a line of their own: badge, name and level, all on one middle line.
    local shown = {}
    for _, m in ipairs(d.people) do if m:IsShown() then shown[#shown + 1] = m end end
    T.truthy(#shown >= 3, "the members and the open spot")
    T.truthy(shown[2].name:GetText():find("Mira Dawnsong", 1, true), "name")
    T.eq(shown[1].level:GetText(), "15", "level")
    for _, m in ipairs(shown) do T.truthy(m.badge:IsShown(), "each line has its role's badge") end
    local _, _, _, _, y1 = shown[1]:GetPoint(1)
    local _, _, _, _, y2 = shown[2]:GetPoint(1)
    T.eq(y1 - y2, d.PERSON or DaylightUI.Social.Detail.PERSON, "one line apart")
    T.eq(shown[#shown].name:GetText(), "Open spot", "the open spots come after the people")
end)

T.test("lfg: group and person rows have a line under them; a picked activity is carried by the wash", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    for _, b in ipairs(rows(ns.Browse.page.stack, "group")) do T.truthy(b.sep:IsShown(), "a group row's line") end
    tab(ns, "who")
    for _, b in ipairs(rows(ns.Who.page.stack, "person")) do T.truthy(b.sep:IsShown(), "a person row's line") end
    tab(ns, "list")
    local acts = rows(ns.Listing.page.stack, "act")
    T.truthy(#acts > 0)
    T.isnil(acts[1].boxEdge, "no hand-built tick box")
    T.falsy(acts[1].pick:IsShown(), "not picked")
    acts[1]:GetScript("OnClick")(acts[1], "LeftButton")
    T.truthy(acts[1].pick:IsShown(), "picked: the wash")
end)

T.test("lfg: the role squares keep the groups that still want that role", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local B = ns.Browse
    local all = #rows(B.page.stack, "group")
    T.truthy(all >= 3)
    local function names() local out = {} for _, b in ipairs(rows(B.page.stack, "group")) do out[#out + 1] = b.spec.result.id end return out end
    local seen = {}
    for _, id in ipairs(names()) do seen[id] = true end
    -- Ask for a role nobody wants: only your own listing (none here) would stay.
    local tank = B.page.needs[1]
    tank:GetScript("OnClick")(tank)
    frame(2)
    local some = #rows(B.page.stack, "group")
    T.truthy(some < all, "fewer groups with a tank wanted: " .. some .. " of " .. all)
    for _, b in ipairs(rows(B.page.stack, "group")) do
        local r = b.spec.result
        local ok
        if r.solo then ok = (r.roles or {}).tank else local _, open = ns.Data.Places(r); ok = open.TANK > 0 end
        T.truthy(ok, "a row that wants or offers a tank")
    end
    tank:GetScript("OnClick")(tank)
    frame(2)
    T.eq(#rows(B.page.stack, "group"), all, "off again: all of them")
end)

T.test("lfg: List yourself keeps its settings in one panel with a line between the rows", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    local page = ns.Listing.page
    T.truthy(page.saved.fill:IsShown(), "the panel")
    local ink = DaylightUI.Style.INK
    T.truthy(page.npfText:GetText() ~= nil, "the switch's label")
    local r, g, b = page.npfText:GetTextColor()
    local lr, lg, lb = page.rolesHead:GetTextColor()
    T.eq(r .. g .. b, lr .. lg .. lb, "the same color as the other labels")
    local tr, tg, tb = ink.LABEL[1], ink.LABEL[2], ink.LABEL[3]
    T.truthy(math.abs(r - tr) < 0.01 and math.abs(g - tg) < 0.01 and math.abs(b - tb) < 0.01, "tan, not the accent")
    local lines = 0
    for _, t in ipairs(page.rules) do if t:IsShown() then lines = lines + 1 end end
    T.eq(lines, 3, "roles | playstyle | note | switch")
    local _, _, _, _, panelTop = page.saved:GetPoint(1)
    local _, _, _, x = page.roleChips[1]:GetPoint(1)
    T.truthy(x >= ns.Listing.EDGE + ns.Listing.IN, "the chips sit inside the panel")
    local _, _, _, _, boxY = page.noteBox:GetPoint(1)
    T.truthy(-boxY > -panelTop and -boxY < -panelTop + page.saved:GetHeight(), "the note box is inside it")
end)

T.test("lfg: List yourself lays its buttons out for the width the window is about to have", function()
    local ns = load()
    local f = open(ns)
    tab(ns, "list")
    local page = ns.Listing.page
    local function rowsOf()
        local ys = {}
        for _, c in ipairs(page.catChips) do
            if c:IsShown() then local _, _, _, _, y = c:GetPoint(1); ys[y] = true end
        end
        local n = 0
        for _ in pairs(ys) do n = n + 1 end
        return n
    end
    -- On the first open the page is still at its old width while the window grows to the
    -- saved, wider size: the four categories should fit in a row for the width coming.
    page.GetWidth = function() return 200 end   -- narrow: the categories would wrap
    f.goalW = f:GetWidth() + 500
    ns.Listing.Render(page)
    T.eq(rowsOf(), 1, "one row of categories")
    f.goalW = ns.Window.W
    ns.Listing.Render(page)
    T.truthy(rowsOf() >= 1)
end)

T.test("lfg: List yourself's role buttons carry a badge, and the panel is padded the same all round", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    local page = ns.Listing.page
    local b = page.roleChips[1]
    T.truthy(b.icon:IsShown(), "the badge")
    T.falsy((b.text:GetText() or ""):find("|T", 1, true) or (b.text:GetText() or ""):find("|A", 1, true), "none drawn inside the text")
    local pad = ns.Listing.IN
    local _, _, _, _, top = page.saved:GetPoint(1)
    local _, _, _, cx, cy = page.roleChips[1]:GetPoint(1)
    T.eq(-cy - (-top), pad, "the same room above the first row")
    T.eq(cx - ns.Listing.EDGE - ns.Listing.LABEL_W, pad, "and at the left (the label's edge)")
    local _, _, _, rx = page.npf:GetPoint(1)
    T.eq(-rx - ns.Listing.EDGE, pad, "and at the right")
    local _, _, _, _, ny = page.npf:GetPoint(1)
    T.near(-ny + page.npf:GetHeight() + pad, -top + page.saved:GetHeight(), 0.5, "and under the last row")
end)

-- The gear's "Show all levels" switch.
T.test("lfg: show all levels adds the activities past your level, to List yourself and the categories, without the client's event", function()
    local ns = load()
    local f = open(ns)
    tab(ns, "list")
    local function names()
        local out = {}
        for _, b in ipairs(rows(ns.Listing.page.stack, "act")) do out[#out + 1] = b.name:GetText() end
        return table.concat(out, "|")
    end
    local cats = #ns.Data.Categories()
    T.falsy(names():find("Scarlet Monastery", 1, true), "past your level: not listed")
    -- The client's CVAR_UPDATE may not come for a change made from code: the menu doesn't wait for it.
    local fire = stub.FireEvent
    stub.FireEvent = function(e, ...) if e == "CVAR_UPDATE" then return end return fire(e, ...) end
    local ok, err = pcall(function()
        ns.Window.OptionsMenu(f.gear)
        ns.Window.SetAllLevels(true)
    end)
    stub.FireEvent = fire
    T.truthy(ok, tostring(err))
    frame(5)
    T.truthy(ns.Window.AllLevels(), "the switch reads on")
    T.truthy(names():find("Scarlet Monastery", 1, true), "now listed: " .. names())
    T.truthy(#ns.Data.Categories() > cats, "and a category that had nothing at your level shows")
    ns.Window.SetAllLevels(false)
    frame(5)
    T.falsy(names():find("Scarlet Monastery", 1, true), "off again")
    DaylightUI.Widgets.CloseMenu()
end)

T.test("lfg: show all levels lights Refresh on Find a group (the groups shown were searched without them)", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local B = ns.Browse
    T.falsy(B.stale)
    ns.Window.SetAllLevels(true)
    frame(2)
    T.truthy(B.stale, "the search is out of date")
    stub.Key(function() B.Refresh() end)
    frame(2)
    T.falsy(B.stale, "searched again")
    -- The new search asks for the activities past your level too.
    local last = LW.Calls("Search")
    local acts = last[#last][2]
    local has = false
    for _, id in ipairs(acts or {}) do if id == 800 then has = true end end
    T.truthy(has, "Scarlet Monastery is in the search")
end)

-- The controller: X presses the card's main button on Find a group and Who. The window binds X for
-- List me itself, so the controller's own footer lookup never applies here.
T.test("lfg: on a controller X presses the card's main button on Find a group and on Who", function()
    local ns = load()
    local f = open(ns)
    local function entry(key)
        for _, e in ipairs(f.padKeys) do
            if e.key == key and (not e.when or e.when()) then return e end
        end
    end
    tab(ns, "find")
    T.isnil(entry("X"), "no card: no X")
    click(rows(ns.Browse.page.stack, "group")[1])
    local x = entry("X")
    T.truthy(x, "X with the card open")
    T.eq(x.label(), "Whisper", "it says what it does")
    local asked = whispers()
    stub.Key(function() x.run() end)
    T.eq(asked[1], "Whisper Gorrak Stonefist")
    -- A player listed alone: Invite is the main button.
    click(rows(ns.Browse.page.stack, "group")[3])
    T.eq(entry("X").label(), "Invite")
    stub.Key(function() entry("X").run() end)
    T.eq(LW.Calls("InviteUnit")[1][1], "Ularanu Seachaser")
    tab(ns, "who")
    T.isnil(entry("X"), "Who has no card open yet (the one on Find belongs to Find)")
    click(rows(ns.Who.page.stack, "person")[1])
    T.eq(entry("X").label(), "Whisper")
    stub.Key(function() entry("X").run() end)
    T.eq(asked[2], "Whisper Daemon Process")
    T.eq(#LW.Calls("SendTell"), 0)
    click(rows(ns.Who.page.stack, "person")[1])
    T.isnil(entry("X"), "card closed: X gone")
    tab(ns, "list")
    T.isnil(entry("X"), "and on List yourself, nothing ticked")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("lfg: the controller's hints are refreshed as the card opens, moves and closes", function()
    local ns = load()
    local f = open(ns)
    tab(ns, "find")
    local P = DaylightUI.Pad
    local calls = 0
    local real = P.Refresh
    P.Refresh = function(fr) if fr == f then calls = calls + 1 end return real(fr) end
    click(rows(ns.Browse.page.stack, "group")[1])
    local opened = calls
    T.truthy(opened > 0, "refreshed when the card opened")
    click(rows(ns.Browse.page.stack, "group")[3])
    T.truthy(calls > opened, "and when it moved to another group")
    P.Refresh = real
end)

-- The game's remaining counts can be off for an activity (The Shaper's Terrace
-- gave four tanks, five healers and two damage still wanted for a five-player
-- group of four). The game's own list draws only the activity's size, so the open
-- places never come to more than the room left.
T.test("lfg places: open spots never come to more than the group's size", function()
    local ns = load()
    local r = { size = 5, members = { {}, {}, {}, {} },
        counts = { TANK = 1, HEALER = 0, DAMAGER = 3, TANK_REMAINING = 4, HEALER_REMAINING = 5, DAMAGER_REMAINING = 2 } }
    local have, open = ns.Data.Places(r)
    T.eq(have.DAMAGER, 3)
    T.eq(open.TANK + open.HEALER + open.DAMAGER, 1, "one place left")
    T.eq(open.HEALER, 1, "the one the five-player shape still lacks")
    -- Counts that fit the room are the game's, as they are.
    r.counts = { TANK = 1, HEALER = 0, DAMAGER = 2, TANK_REMAINING = 0, HEALER_REMAINING = 1, DAMAGER_REMAINING = 1 }
    r.members = { {}, {}, {} }
    _, open = ns.Data.Places(r)
    T.eq(open.HEALER, 1); T.eq(open.DAMAGER, 1); T.eq(open.TANK, 0)
end)

-- A ten-player group (Upper Blackrock Spire) of nine: the game's own tooltip names every
-- member of a group up to ten, so the card and tooltip must too, classes and all.
local function bigGroup(n, act)
    local classes = { "WARRIOR", "PRIEST", "ROGUE", "MAGE", "WARLOCK", "HUNTER", "DRUID", "PALADIN", "MAGE", "ROGUE", "PRIEST", "WARRIOR" }
    local roles = { "TANK", "HEALER" }
    local members = {}
    for i = 1, n do
        members[i] = { name = "Raider" .. i, classFilename = classes[(i - 1) % #classes + 1], level = 60,
            assignedRole = roles[i] or "DAMAGER", areaName = i == 1 and "Burning Steppes" or nil }
    end
    return { { id = 40, activityIDs = { act }, age = 60, comment = "class run", generalPlaystyle = 2, members = members } }
end

T.test("lfg: a ten-player group shows every member by name, on the card and the tooltip", function()
    local ns = load({ results = bigGroup(9, 801), level = 60 })
    open(ns)
    tab(ns, "find")
    local row = rows(ns.Browse.page.stack, "group")[1]
    T.truthy(row, "the group is listed")
    local tip = recordTips()
    row:GetScript("OnEnter")(row)
    local text = table.concat(tip.lines, "\n")
    for i = 1, 9 do T.truthy(text:find("Raider" .. i, 1, true), "tooltip names Raider" .. i .. ": " .. text) end
    T.truthy(text:find("Warlock", 1, true), "with each class: " .. text)
    click(row)
    local lines = card(ns.Browse.page.detail)
    local group = lines["In the group"] or ""
    for i = 1, 9 do T.truthy(group:find("Raider" .. i, 1, true), "card names Raider" .. i .. ": " .. group) end
end)

T.test("lfg: a raid too big to name shows how many of each class are in", function()
    local ns = load({ results = bigGroup(12, 900), level = 60 })
    open(ns)
    tab(ns, "find")
    stub.Key(function() ns.Browse.PickCat(114) end)
    frame(20)
    local row = rows(ns.Browse.page.stack, "group")[1]
    T.truthy(row, "the raid is listed")
    local tip = recordTips()
    row:GetScript("OnEnter")(row)
    local text = table.concat(tip.lines, "\n")
    T.truthy(text:find("12 / 40", 1, true), "how many of how many: " .. text)
    T.truthy(text:find("Warrior", 1, true) and text:find("Mage", 1, true) and text:find("Paladin", 1, true), "the classes: " .. text)
    click(row)
    local lines = card(ns.Browse.page.detail)
    local all = {}
    for k, v in pairs(lines) do all[#all + 1] = tostring(k) .. "=" .. tostring(v) end
    all = table.concat(all, "\n")
    T.truthy(all:find("Mage", 1, true) and all:find("Paladin", 1, true), "the card has the classes: " .. all)
end)

T.test("lfg: a full ten-player group with a long note still names everyone on the card", function()
    local res = bigGroup(10, 801)
    res[1].comment = "LFM good old fast class run, nothing reserved on the Hand of Ragnaros, need key, bring health pots and fire resist, summons at the stone"
    res[1].isDelisted = true
    local ns = load({ results = res, level = 60 })
    open(ns)
    tab(ns, "find")
    click(rows(ns.Browse.page.stack, "group")[1])
    local lines = card(ns.Browse.page.detail)
    local group = lines["In the group"] or ""
    for i = 1, 10 do T.truthy(group:find("Raider" .. i, 1, true), "card names Raider" .. i .. ": " .. group) end
    T.truthy(lines.Note, "the note too")
end)
