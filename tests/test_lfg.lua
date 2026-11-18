local stub = require("stub")
local LW = require("lfgworld")

-- The group finder window.

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

-- The names the category drop-down offers.
local function categoryChoices(ns)
    local names = {}
    for _, c in ipairs(ns.Data.Categories()) do names[#names + 1] = c.name end
    return table.concat(names, ", ")
end

T.test("lfg: the category drop-down lists what's there at your level", function()
    local ns = load()
    open(ns)
    T.eq(categoryChoices(ns), "Dungeons, Quests & Zones, Custom", "Raids: nothing at level 14")
    local page = ns.Listing.page
    T.truthy(page.cat.chevron, "a drop-down, no chips")
    T.eq(page.catLabel:GetText(), "Category")
    T.eq(page.sortByLabel:GetText(), "Sort by")
    T.truthy(ns.Listing.labelW >= ns.Listing.LABEL_W, "a label column wide enough for the longest label")
    T.eq(page.cat.text:GetText(), ns.Listing.CategoryWord())
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
    T.truthy(categoryChoices(ns):find("Raids", 1, true), "Raids at level 14 once every level shows")
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

-- Category and activity are drop-downs, each with its word over it, so no name can run
-- past the window's edge in any language.
T.test("lfg: category and activity are labeled drop-downs; the list sits under them", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local page = ns.Browse.page
    T.isnil(page.chips, "no chips")
    -- The filters sit in a panel with a bar down its left edge, and the list under it.
    T.truthy(page.panel.fill:IsShown() and page.panel.edge:IsShown(), "the panel and its side bar")
    local function top(f) for n = 1, f:GetNumPoints() do local pt, _, _, _, py = f:GetPoint(n); if pt == "TOPLEFT" then return py end end end
    T.truthy(-top(page.stack.scroll) >= -top(page.panel) + page.panel:GetHeight(), "the list under the panel")
    T.truthy(-select(5, page.refresh:GetPoint(1)) + page.refresh:GetHeight() <= -top(page.panel) + page.panel:GetHeight(), "Refresh inside it")
    T.truthy(page.cat.chevron and page.act.chevron, "menu buttons")
    T.truthy(type(page.cat:GetWidth()) == "number" and page.cat:GetWidth() > 100, "the layout gives each a width")
    T.truthy(type(page.act:GetWidth()) == "number" and page.act:GetWidth() > 100)
    -- The roles: each button has its badge and its word, under the drop-downs.
    T.eq(page.rolesLabel:GetText(), "Roles")
    for _, b in ipairs(page.needs) do
        T.truthy(b.icon and b.text:GetText() ~= "", "badge and word: " .. tostring(b.text:GetText()))
    end
    T.eq(page.needs[1].text:GetText(), "Tank")
    T.eq(page.catLabel:GetText(), "Category")
    T.eq(page.actLabel:GetText(), "Activity")
    T.eq(page.cat.text:GetText(), "Dungeons")
    local right = ns.Browse.Width(page) - ns.Browse.EDGE
    local _, _, _, x = page.act:GetPoint(1)
    T.truthy(ns.Browse.EDGE + page.cat:GetWidth() + x > 0 and x >= 0, "side by side")
    T.truthy(ns.Browse.EDGE + page.cat:GetWidth() + page.act:GetWidth() < right, "inside the window")
    local sy
    for n = 1, page.stack.scroll:GetNumPoints() do
        local pt, _, _, _, py = page.stack.scroll:GetPoint(n)
        if pt == "TOPLEFT" then sy = py end
    end
    local _, _, _, _, cy = page.cat:GetPoint(1)
    T.truthy(-sy >= -cy + page.cat:GetHeight(), "the list under the drop-downs")
    -- The category menu lists them all, and picking one searches it.
    local before = #LW.Calls("Search")
    page.cat:Click()
    local row
    for i = 1, 6 do
        local r = DaylightUI.Widgets.MenuRow(i)
        if r and r:IsShown() and r.text:GetText() == "Quests & Zones" then row = r end
    end
    T.truthy(row, "Quests & Zones in the menu")
    stub.Key(function() row:Click() end)
    T.eq(page.cat.text:GetText(), "Quests & Zones")
    T.truthy(#LW.Calls("Search") > before, "a new category searches")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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
    T.eq((row.note:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), "Note: need dps", "Note:, then the note")
    T.truthy(row.note:GetText():find("^|c%x%x%x%x%x%x%x%xNote:|r need dps$"), "the word apart, in the tan of the labels")
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

-- After a new listing the game searches only that listing's activities, and an
-- addon can't search without a click. Find says so, and one click on its button
-- shows every group of the category. In game it showed "All activities" over only
-- three Stockades groups.
local function listedIDs(ns) return table.concat(ns.Data.Entry().activityIDs, ",") end

T.test("lfg: after listing, Find names what was searched; Refresh keeps it, All activities searches the whole category", function()
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
    T.isnil(B.page.all, "no Show all button: the drop-down does it")
    local before = #rows(B.page.stack, "group")
    stub.Key(function() B.page.refresh:GetScript("OnClick")(B.page.refresh) end)
    frame(20)
    local s = LW.Calls("Search")
    T.eq(table.concat(s[#s][2], ","), listedIDs(ns), "Refresh searches what's shown again")
    T.eq(B.page.act.text:GetText(), listed, "still narrowed")
    stub.Key(function() B.PickActivity(nil) end)
    frame(20)
    s = LW.Calls("Search")
    T.eq(#s[#s][2], #ns.Data.Filtered(2), "every activity of the category")
    T.eq(B.page.act.text:GetText(), "All activities")
    T.truthy(#rows(B.page.stack, "group") > before, "the other groups show")
end)

T.test("lfg: a search the game never answers stops saying Searching... and says it failed", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local B = ns.Browse
    LW.state.silentSearch = true
    stub.Key(function() B.Refresh() end)
    T.eq(B.page.note:GetText(), "Searching...")
    T.truthy(B.page.seek:IsShown(), "the bar")
    stub.RunTimers()
    T.falsy(B.searching, "no longer waiting")
    T.eq(B.page.note:GetText(), "The search failed. Try Refresh.")
    T.falsy(B.page.seek:IsShown())
    LW.state.silentSearch = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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
    d.buttons[1]:GetScript("OnClick")(d.buttons[1])
    T.eq(LW.Calls("SendTell")[1][1], "Gorrak Stonefist")
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
    T.truthy(-oy <= 260, "the activities start high: " .. tostring(-oy))
    T.eq(page.rolesHead:GetText(), "Roles")
    local _, _, _, rx = page.roleChips[1]:GetPoint(1)
    T.eq(rx, ns.Listing.EDGE + ns.Listing.IN + ns.Listing.labelW, "the buttons beside their label")
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

T.test("lfg: List yourself sorts activities by level or A to Z from a drop-down, and keeps the pick", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    local L = ns.Listing
    T.eq(texts(rows(L.page.stack, "act")), "Wailing Caverns | Ragefire Chasm", "by level at first")
    T.eq(L.page.sortBy.text:GetText(), "Level")
    T.truthy(L.page.sortBy.chevron, "a menu button")
    local _, _, _, sx, sortTop = L.page.sortBy:GetPoint(1)
    local _, _, _, cx, catTop = L.page.cat:GetPoint(1)
    T.eq(sx, cx, "lined up with the category drop-down")
    T.truthy(sortTop < catTop, "a row under it, in the same panel")
    local _, _, _, _, panelTop = L.page.saved:GetPoint(1)
    T.truthy(-sortTop < -panelTop + L.page.saved:GetHeight(), "inside the panel")
    L.PickSort("name")
    frame(5)
    T.eq(DaylightUI:Get("GroupFinder", "activitySort"), "name", "saved")
    T.eq(texts(rows(L.page.stack, "act")), "Ragefire Chasm | Wailing Caverns", "A to Z")
    T.eq(L.page.sortBy.text:GetText(), "Name")
    -- Find's activity menu follows the same order.
    T.eq(ns.Data.Groups(2)[1].acts[1].name, "Ragefire Chasm")
    L.PickSort("level")
    frame(5)
    T.eq(DaylightUI:Get("GroupFinder", "activitySort"), "level")
    T.eq(L.page.sortBy.text:GetText(), "Level")
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
    d.buttons[1]:GetScript("OnClick")(d.buttons[1])
    T.eq(LW.Calls("SendTell")[1][1], "Daemon Process")
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

T.test("lfg: Who filters by race, class and zone in the /who itself, each a labeled drop-down", function()
    local ns = load()
    open(ns)
    tab(ns, "who")
    local W, page = ns.Who, ns.Who.page
    T.truthy(page.panel.fill:IsShown() and page.panel.edge:IsShown(), "the filters' panel with its side bar")
    local function top(f) for n = 1, f:GetNumPoints() do local pt, _, _, _, py = f:GetPoint(n); if pt == "TOPLEFT" then return py end end end
    T.truthy(-select(5, page.sortBy:GetPoint(1)) + page.sortBy:GetHeight() <= -top(page.panel) + page.panel:GetHeight(), "the drop-downs inside it")
    T.truthy(-top(page.stack.scroll) >= -top(page.panel) + page.panel:GetHeight(), "the list under it")
    T.eq(page.raceLabel:GetText(), "Race")
    T.eq(page.classLabel:GetText(), "Class")
    T.eq(page.zoneLabel:GetText(), "Zone")
    T.eq(page.sortByLabel:GetText(), "Sort by")
    for _, key in ipairs({ "race", "class", "zone", "sortBy" }) do
        T.truthy(page[key].chevron, key .. " is a menu button")
    end
    T.eq(page.race.text:GetText(), "All", "no filter: everyone")
    T.eq(W.Query(""), "14", "nothing set: your level, as before")
    W.race, W.class, W.zone = "Orc", "WARLOCK", "Agama'gor"
    T.eq(W.Query("dae"), 'dae r-"Orc" c-"Warlock" z-"Agama\'gor"')
    W.race, W.class, W.zone = nil, nil, nil
    -- Picking a race only sets it: nothing goes to the game until Search.
    local before = #LW.Calls("SendWho")
    stub.Advance(3)   -- the game wants a few seconds between two /who
    W.race = "Orc"; W.Changed()
    W.class = "WARLOCK"; W.Changed()
    T.eq(#LW.Calls("SendWho"), before, "a filter asks nothing")
    T.truthy(page.go.active, "Search lit: what is set is not what was asked")
    stub.Key(function() page.go:GetScript("OnClick")(page.go) end)
    T.eq(#LW.Calls("SendWho"), before + 1, "Search asks once, with both filters")
    T.eq(LW.Calls("SendWho")[before + 1][1], 'r-"Orc" c-"Warlock"')
    W.class = nil
    T.eq(page.race.text:GetText(), "Orc", "the drop-down shows what is picked")
    T.truthy(page.go.off, "Search is off while the game is asked")
    -- Asking: the list says so, with the bar, until the answer comes.
    T.eq(page.note:GetText(), "Searching...")
    T.truthy(page.note:IsShown() and page.seek:IsShown(), "Searching... and its bar")
    T.eq(#rows(page.stack, "person"), 0, "the old answer is gone while asking")
    frame(5)
    T.falsy(page.seek:IsShown(), "the answer is in")
    T.eq(#rows(page.stack, "person"), 2)
    -- The zones on offer are the ones in the answer.
    local zones = W.Zones()
    T.truthy(tContains(zones, "Boulder Lode Mine"), "a zone from the answer")
    -- Reset: filters and box cleared; it asks nothing, Search then asks for your level.
    T.truthy(W.Filtered(), "a filter is on")
    page.search:SetText("lava")
    local sent = #LW.Calls("SendWho")
    stub.Key(function() page.reset:GetScript("OnClick")(page.reset) end)
    T.isnil(W.race, "race cleared")
    T.eq(page.search:GetText(), "", "the box too")
    T.eq(#LW.Calls("SendWho"), sent, "Reset asks nothing")
    T.falsy(W.Filtered(), "nothing to reset now")
    T.truthy(page.reset.off, "Reset is off with nothing set")
    stub.Advance(3)
    stub.Key(function() page.go:GetScript("OnClick")(page.go) end)
    T.eq(LW.Calls("SendWho")[#LW.Calls("SendWho")][1], "14", "Search asks for your level again")
    frame(5)
    -- No answer in time: stop asking and say so.
    LW.state.silentWho = true
    stub.Advance(3)
    stub.Key(function() W.Send("x") end)
    T.eq(page.note:GetText(), "Searching...")
    stub.RunTimers()
    T.falsy(page.seek:IsShown(), "no longer waiting")
    T.eq(page.note:GetText(), "Nothing came back. Press Enter to search again.")
    LW.state.silentWho = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game says "You must wait 2 s before using /who again" and drops the search: our
-- controls are off for that time, and a send in it is not made.
T.test("lfg: Who waits out the game's two seconds between searches", function()
    local ns = load()
    open(ns)
    tab(ns, "who")
    local W, page = ns.Who, ns.Who.page
    frame(5)
    T.truthy(W.Cooling(), "just asked: still within the two seconds")
    T.truthy(page.go.off, "Search is off meanwhile")
    T.falsy(page.race.off, "the filters can still be set")
    local before = #LW.Calls("SendWho")
    stub.Key(function() W.race = "Orc"; T.falsy(W.Send(""), "refused, not sent") end)
    T.eq(#LW.Calls("SendWho"), before, "nothing went to the game")
    W.race = nil
    stub.Advance(3)
    stub.RunTimers()
    W.Render()   -- what the wait's timer does when the time is up
    T.falsy(W.Cooling())
    T.falsy(page.go.off, "Search back on after the wait")
    stub.Key(function() W.Send("") end)
    T.eq(#LW.Calls("SendWho"), before + 1, "and a search goes through")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("lfg: when the game refuses a /who with its wait, Who shows that sentence and waits that long", function()
    local ns = load()
    open(ns)
    tab(ns, "who")
    local W, page = ns.Who, ns.Who.page
    LW.state.silentWho = true
    stub.Advance(10)
    stub.Key(function() W.Send("x") end)
    T.truthy(W.searching)
    local before = W.COOL
    stub.Advance(1)
    local sentence = "You must wait 4 s. before using /who again."
    stub.FireEvent("UI_ERROR_MESSAGE", 1, sentence)
    T.falsy(W.searching, "not waiting for an answer that will not come")
    T.eq(page.note:GetText(), sentence, "the game's own sentence")
    T.truthy(W.Cooling() and page.go.off, "Search off for the wait")
    T.truthy(W.COOL >= 5, "the next waits learn how long the game wants: " .. W.COOL)
    T.truthy(W.COOL > before)
    -- Some other error line is not ours.
    stub.Advance(10)
    stub.Key(function() W.Send("y") end)
    stub.Advance(30)
    stub.FireEvent("UI_ERROR_MESSAGE", 1, "Out of range 5")
    T.truthy(W.searching, "too late to be the answer to our /who: ignored")
    LW.state.silentWho = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("lfg: a Who row's level is the game's own template with the plain number, the number colored", function()
    local ns = load()
    _G.UNIT_LEVEL_TEMPLATE = "Nivel %d"
    local ok, err = pcall(function()
        local word = ns.Who and ns.Who.LevelWord
        open(ns)
        word = ns.Who.LevelWord
        local plain = word(25):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        T.eq(plain, "Nivel 25")
        T.truthy(word(25):find("|c", 1, true), "the number colored")
        _G.UNIT_LEVEL_TEMPLATE = nil
        T.eq((word(25):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), "Level 25", "the word and the number without it")
    end)
    _G.UNIT_LEVEL_TEMPLATE = nil
    if not ok then error(err, 0) end
end)

T.test("lfg: a Who row has the class icon on the left, name over level, race and class, zone on the right", function()
    local ns = load()
    local keep = DaylightUI.ClassIcon
    DaylightUI.ClassIcon = function(token) return "icon-" .. token, 0, 1, 0, 1 end
    local ok, err = pcall(function()
        open(ns)
        tab(ns, "who")
        local list = rows(ns.Who.page.stack, "person")
        T.eq(#list, 2)
        T.truthy(list[1].icon:IsShown(), "the class icon")
        T.eq(list[1].icon:GetTexture(), "icon-WARLOCK")
        local sub = list[1].sub:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        T.truthy(sub:find("Level 14", 1, true) and not sub:find("Level 0", 1, true), "the level, never 0")
        T.truthy(sub:find("Level 14", 1, true) and sub:find("Orc", 1, true) and sub:find("Warlock", 1, true), sub)
        T.truthy(sub:find("·", 1, true), "level, race and class set apart")
        T.eq(list[1].value:GetText(), "Agama'gor", "the zone on the right")
        -- The text starts after the icon.
        local _, _, _, nameX = list[1].name:GetPoint(1)
        T.truthy(nameX >= ns.Rows.ICON + 8, "the name clears the icon")
    end)
    DaylightUI.ClassIcon = keep
    if not ok then error(err, 0) end
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
    T.eq(lines, 5, "roles | playstyle | note | switch | category | sort")
    local _, _, _, _, panelTop = page.saved:GetPoint(1)
    local _, _, _, x = page.roleChips[1]:GetPoint(1)
    T.truthy(x >= ns.Listing.EDGE + ns.Listing.IN, "the chips sit inside the panel")
    local _, _, _, _, boxY = page.noteBox:GetPoint(1)
    T.truthy(-boxY > -panelTop and -boxY < -panelTop + page.saved:GetHeight(), "the note box is inside it")
end)

T.test("lfg: List yourself's drop-downs fill the panel for the width the window is about to have", function()
    local ns = load()
    local f = open(ns)
    tab(ns, "list")
    local page = ns.Listing.page
    -- On the first open the page is still at its old width while the window grows to the
    -- saved, wider size: the drop-downs take the width coming.
    page.GetWidth = function() return 200 end
    f.goalW = f:GetWidth() + 500
    ns.Listing.Render(page)
    T.truthy(page.cat:GetWidth() > 400, "wide for the window coming, not the page as it is")
    T.eq(page.cat:GetWidth(), page.sortBy:GetWidth(), "the same width")
    f.goalW = ns.Window.W
    ns.Listing.Render(page)
    T.truthy(page.cat:GetWidth() >= 120)
end)

T.test("lfg: List yourself's activities have a tick box that follows the pick", function()
    local ns = load()
    open(ns)
    tab(ns, "list")
    local acts = rows(ns.Listing.page.stack, "act")
    T.truthy(#acts >= 1)
    T.truthy(acts[1].boxOut:IsShown() and acts[1].boxIn:IsShown(), "a box to tick")
    T.falsy(acts[1].tick:IsShown(), "empty at first")
    acts[1]:GetScript("OnClick")(acts[1], "LeftButton")
    T.truthy(acts[1].tick:IsShown(), "ticked once picked")
    acts[1]:GetScript("OnClick")(acts[1], "LeftButton")
    T.falsy(acts[1].tick:IsShown(), "empty again")
    -- Rows that are not ticked have no box (the groups, the people).
    tab(ns, "who")
    for _, b in ipairs(rows(ns.Who.page.stack, "person")) do T.falsy(b.boxOut:IsShown(), "no box on a person") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("lfg: the new-player switch says the game's own sentence, wrapped beside the switch", function()
    local sentence = "Indica que aceptas a jugadores nuevos en tu grupo y que estas dispuesto a hacer de guia."
    _G.LFG_LIST_NEW_PLAYER_FRIENDLY_TOOLTIP = sentence
    local ns = load()
    local ok, err = pcall(function()
        open(ns)
        tab(ns, "list")
        local page = ns.Listing.page
        T.eq(page.npfText:GetText(), sentence)
        T.truthy(page.npfText:GetWidth() <= ns.Window.W - 2 * (ns.Listing.EDGE + ns.Listing.IN) - page.npf:GetWidth(), "it leaves room for the switch")
    end)
    _G.LFG_LIST_NEW_PLAYER_FRIENDLY_TOOLTIP = nil
    if not ok then error(err, 0) end
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
    T.eq(cx - ns.Listing.EDGE - ns.Listing.labelW, pad, "and at the left (the label's edge)")
    local _, _, _, rx = page.npf:GetPoint(1)
    T.eq(-rx - ns.Listing.EDGE, pad, "and at the right")
    local _, _, _, _, sy = page.sortBy:GetPoint(1)
    T.near(-sy + page.sortBy:GetHeight() + pad, -top + page.saved:GetHeight(), 0.5, "and under the last row, the Sort by drop-down")
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
    stub.Key(function() x.run() end)
    T.eq(LW.Calls("SendTell")[1][1], "Gorrak Stonefist")
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
    T.eq(LW.Calls("SendTell")[2][1], "Daemon Process")
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
