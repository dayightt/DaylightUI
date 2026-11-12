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
    T.eq(DaylightUI.lfgOwnWindow, true)
    T.truthy(stub.lfg.Window.frame, "built")
end)

T.test("lfg: switched off, the game's window stays the game's", function()
    local ns = load({ enabled = false })
    T.eq(DaylightUI.lfgOwnWindow, false)
    T.isnil(ns.Window.frame, "nothing built")
    LW.Toggle(1)
    frame(5)
    T.eq(LFGParentFrame:GetParent(), UIParent, "not parked")
    T.truthy(LFGParentFrame:IsVisible(), "the game's own window shows")
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
    T.truthy(f.headerRight, "a gear left of the X")
    stub.Key(function() f.headerRight:GetScript("OnClick")(f.headerRight) end)
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

T.test("lfg: the leader's zone shows on the row, the tooltip and the opened group", function()
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
    local d = ns.Browse.page.stack.openedFrame
    T.truthy(d.lines[1].what:GetText():find("Westfall", 1, true), "beside the leader in the opened group")
    T.falsy(d.lines[2].what:GetText():find("Westfall", 1, true), "the zone is the leader's alone")
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
    local d = B.opened
    T.eq(d.second.text:GetText(), "Unlist")
    d.second:GetScript("OnClick")(d.second)
    frame(20)
    T.eq(#LW.Calls("RemoveListing"), 1)
    T.isnil(mine(), "your row is gone without a Refresh")
    T.isnil(B.open, "nothing of yours left open")
end)

T.test("lfg: a click opens the group in place: Whisper the leader, no Invite for a group", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local row = rows(ns.Browse.page.stack, "group")[1]
    stub.Key(function() row:GetScript("OnClick")(row, "LeftButton") end)
    frame(20)
    T.eq(ns.Browse.open, 17)
    local d = ns.Browse.opened
    T.truthy(d and d:IsShown(), "opened")
    T.near(d:GetHeight(), d.full, 0.5, "glided fully open")
    T.eq(d.main.text:GetText(), "Whisper Gorrak Stonefist")
    T.truthy(d.second.off, "only a player listed alone can be invited")
    d.main:GetScript("OnClick")(d.main)
    T.eq(LW.Calls("SendTell")[1][1], "Gorrak Stonefist")
    -- Clicked again: it glides shut.
    stub.Key(function() row:GetScript("OnClick")(row, "LeftButton") end)
    frame(20)
    T.isnil(ns.Browse.open)
end)

-- With one row open, clicking another glides the first shut, then opens the
-- second, even when a listing change redraws the list mid-glide.
T.test("lfg: another group clicked opens once the first has shut, a refill midway or not", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local list = rows(ns.Browse.page.stack, "group")
    stub.Key(function() list[1]:GetScript("OnClick")(list[1], "LeftButton") end)
    frame(20)
    T.eq(ns.Browse.open, 17)
    list = rows(ns.Browse.page.stack, "group")
    stub.Key(function() list[2]:GetScript("OnClick")(list[2], "LeftButton") end)
    frame(2)   -- the first gliding shut
    LW.Update(17, {})
    frame(20)
    T.truthy(ns.Browse.open and ns.Browse.open ~= 17, "the second one open")
    local d = ns.Browse.opened
    T.truthy(d and d:IsShown(), "drawn open")
    T.near(d:GetHeight(), d.full, 0.5, "glided fully open")
end)

-- The list redrawn mid-glide by a listing change. The old glide's rows are pooled
-- and placed anew, so the glide must stop moving them.
T.test("lfg: drawn again while a group glides open, the rows land where the new list puts them", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local row = rows(ns.Browse.page.stack, "group")[1]
    stub.Key(function() row:GetScript("OnClick")(row, "LeftButton") end)
    frame(2)   -- gliding
    ns.Browse.open = nil
    ns.Browse.Render(nil, true)
    frame(20)
    local function ys()
        local out = {}
        for _, p in ipairs(ns.Browse.page.pieces) do local _, _, _, _, y = p:GetPoint(1); out[#out + 1] = tostring(y) end
        return table.concat(out, " ")
    end
    local after = ys()
    ns.Browse.Render(nil, true)
    T.eq(after, ys())
end)

T.test("lfg: a player listed alone can be invited", function()
    local ns = load()
    open(ns)
    tab(ns, "find")
    local solo = rows(ns.Browse.page.stack, "group")[3]
    stub.Key(function() solo:GetScript("OnClick")(solo, "LeftButton") end)
    frame(20)
    local d = ns.Browse.opened
    T.falsy(d.second.off)
    d.second:GetScript("OnClick")(d.second)
    T.eq(LW.Calls("InviteUnit")[1][1], "Ularanu Seachaser")
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
    T.truthy(-oy <= 180, "the activities start high: " .. tostring(-oy))
    T.eq(page.rolesHead:GetText(), "Roles")
    local _, _, _, rx = page.roleChips[1]:GetPoint(1)
    T.eq(rx, ns.Listing.EDGE + ns.Listing.LABEL_W, "the buttons beside their label")
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
    T.truthy(ns.Who.page.foot.buttons[1].spec.off, "no one picked")
    list[1]:GetScript("OnClick")(list[1], "LeftButton")
    T.falsy(ns.Who.page.foot.buttons[1].spec.off)
    ns.Who.page.foot.buttons[1]:GetScript("OnClick")(ns.Who.page.foot.buttons[1])
    T.eq(LW.Calls("SendTell")[1][1], "Daemon Process")
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
    local row = rows(ns.Browse.page.stack, "group")[1]
    stub.Key(function() row:GetScript("OnClick")(row, "LeftButton") end)
    T.near(ns.Browse.opened:GetHeight(), ns.Browse.opened.full, 0.5)
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
