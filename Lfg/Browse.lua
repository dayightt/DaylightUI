-- Find a group: category buttons, an activity drop-down and the roles in one filter panel, then the
-- last search's listings in the game's order. The player's own first, then groups and
-- solo players (reversed while in a group). Hovering a listing shows the whole party in
-- a tooltip. Clicking picks it and opens a detail card beside the list (Social's,
-- DUI.Social.Detail: the leader, the activity, the note, the members and open spots,
-- Whisper and Invite); click again to close it. Right-click gives Whisper / Invite at
-- the cursor.
--
-- C_LFGList.Search is allowed from addon code. Results come from the client's single
-- list (GetFilteredSearchResults), so a search the game makes itself (after listing)
-- fills this one too.

local _, DUI = ...
DUI.Lfg = DUI.Lfg or {}
local ns = DUI.Lfg
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Browse = {}
ns.Browse = Browse

Browse.EDGE = 16
Browse.PANEL_Y = 10      -- the filters' panel
Browse.LABEL_Y = 22      -- the small word over the category buttons
Browse.CHIPS_Y = 36      -- the category buttons' first row
Browse.PANEL_PAD = 12    -- under the panel's last row
Browse.TOP_GAP = 10      -- from the panel to the list
Browse.TOP = 170         -- the list's top before the bar is laid out (one row of categories)
Browse.SEEK = 0.8        -- s for the searching bar to fill, repeated
Browse.SEEK_W = 140
Browse.SPLIT_W = 800      -- list width from which groups and solo players sit side by side
Browse.WAIT = 3          -- s to wait for the game's own search first
Browse.LOST = 6          -- s without an answer to our own search before it counts as lost
Browse.need = {}         -- role -> true: only the groups that still want it (or the players who offer it)
Browse.EVENTS = { "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_FAILED", "LFG_LIST_SEARCH_RESULT_UPDATED",
    "LFG_LIST_AVAILABILITY_UPDATE", "GROUP_ROSTER_UPDATE", "LFG_LIST_ACTIVE_ENTRY_UPDATE" }

-- The words over the buttons and the drop-down: the game's own where it has them.
function Browse.CatWord() return _G.CATEGORY or L["Category"] end
function Browse.ActWord() return _G.LFG_LIST_ACTIVITY or L["Activity"] end

local function W() return DUI.Widgets end
local function Data() return ns.Data end
local function Card() return DUI.Social.Detail end
local ROLE_ICON, ROLE_GAP = 16, 6   -- a role button's badge, and the space before its word

-- Searching

-- Category to show: the selected one, else the listing's, else the first.
function Browse.PickCategory()
    local cats = Data().Categories()
    for _, c in ipairs(cats) do if c.id == Browse.cat then return c.id end end
    local e = Data().Entry()
    local a = e and Data().Activity(e.activityIDs[1])
    if a then
        for _, c in ipairs(cats) do if c.id == a.categoryID then return c.id end end
    end
    return cats[1] and cats[1].id or nil
end

-- Like LFGBrowse_DoSearch: every activity in the category at the player's level.
-- Picking an activity only narrows what's shown (Browse.Render) and never searches
-- again, because the game blocked a search from the menu's click.
local received

function Browse.Search(only)
    local cat = Browse.PickCategory()
    Browse.cat = cat
    if not cat then return Browse.Render() end
    local acts = only or Data().Filtered(cat)
    Browse.searching, Browse.failed, Browse.open = true, false, nil
    Browse.searched, Browse.ours, Browse.narrow, Browse.stale = true, true, only, nil
    Data().Ask("Search", cat, 0, 0, nil, false, nil, acts)
    -- The game may let nothing through (a search it refused leaves no answer): stop waiting.
    Browse.token = (Browse.token or 0) + 1
    local mine = Browse.token
    C_Timer.After(Browse.LOST, function()
        if Browse.token == mine and Browse.searching and Browse.ours then received(true) end
    end)
    Browse.Render()
end

-- Refresh repeats what's shown (only the listing's activities while narrowed to them);
-- Show all searches the whole category. Two buttons, never one that changes meaning.
function Browse.Refresh() Browse.Search(Browse.narrow) end
function Browse.ShowAll() Browse.Search() end

-- Activities the game searched (the listing's) as plain ids; nil = none.
local function plainIDs(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, id in ipairs(list) do
        local v = Data().Plain(id)
        if type(v) == "number" then out[#out + 1] = v end
    end
    return #out > 0 and out or nil
end

-- The game searched for a new listing on its own (its code is untainted; an addon
-- search needs a click or key). Show that category and wait for the results, giving up
-- after Browse.WAIT s. The game only searches those activities
-- (LFGParentFrame_SearchActiveEntry), so Browse.narrow keeps them: the activity button
-- names them and Refresh becomes Show all, since otherwise only a few groups show up.
function Browse.Listed(acts)
    local e = Data().Entry()
    Browse.narrow = plainIDs(acts) or plainIDs(e and e.activityIDs)
    local a = Data().Activity(Browse.narrow and Browse.narrow[1])
    if a then Browse.cat = a.categoryID end
    Browse.act, Browse.open = nil, nil
    Browse.searching, Browse.failed, Browse.searched = true, false, true
    Browse.waitFor = (Browse.waitFor or 0) + 1
    local mine = Browse.waitFor
    C_Timer.After(Browse.WAIT, function()
        if Browse.waitFor == mine and Browse.searching then
            Browse.searching = false
            Browse.results = Data().Results()
            Browse.fresh = true
            Browse.Render(nil, true)
        end
    end)
    Browse.Render()
end

function received(failed)
    Browse.searching = false
    Browse.failed = failed == true
    Browse.waitFor = (Browse.waitFor or 0) + 1
    -- Closed while the game's finder searched: read when it opens (Browse.Fill).
    if not (Browse.page and Browse.page:IsVisible()) then return end
    Browse.results = failed and {} or Data().Results()
    if Browse.open then
        local still = false
        for _, r in ipairs(Browse.results) do if r.id == Browse.open then still = true end end
        if not still then Browse.open = nil end
    end
    Browse.fresh = true   -- new results: rows lift in one after another
    Browse.Render(nil, true)
end

-- A listing changed (LFG_LIST_SEARCH_RESULT_UPDATED, often many at once; the player's
-- own via LFG_LIST_ACTIVE_ENTRY_UPDATE): re-read next frame, only while shown.
function Browse.Soon()
    local page = Browse.page
    if not (page and page:IsVisible()) or Browse.pending or Browse.searching then return end
    Browse.pending = true
    C_Timer.After(0, function()
        Browse.pending = nil
        if not page:IsVisible() or Browse.searching then return end
        Browse.results = Data().Results()
        Browse.Render(nil, true)
    end)
end

-- The bar: the category buttons with their word over them (a click picks one and searches it),
-- under them the Activity drop-down with its word, and under that the Roles buttons on the left
-- and, on the right, Show all (while narrowed to the listing's activities), Reset and Refresh.

-- Page width (the target width while the window is resizing).
function Browse.Width(page)
    return page.stack:Width() + 2 * Win.Parts.EDGE
end

-- width is the page's width while the window is being dragged (a size change), else the one
-- it is going to.
local function layoutBar(page, width)
    local W_ = W()
    local R = ns.Rows
    local room = Browse.room or 0
    local x = Browse.EDGE + R.PANEL_IN          -- inside the panel
    local inner = (width or Browse.Width(page)) - room - 2 * Browse.EDGE - 2 * R.PANEL_IN
    local h, gap = W_.CHIP_HEIGHT, W_.CHIP_GAP
    page.panel:ClearAllPoints()
    page.panel:SetPoint("TOPLEFT", page, "TOPLEFT", Browse.EDGE, -Browse.PANEL_Y)
    page.panel:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Browse.EDGE - room, -Browse.PANEL_Y)
    -- The category buttons wrap onto more rows as the window narrows.
    page.catLabel:ClearAllPoints()
    page.catLabel:SetPoint("TOPLEFT", page, "TOPLEFT", x + 2, -Browse.LABEL_Y)
    local cx, cy = 0, Browse.CHIPS_Y
    for _, b in ipairs(page.chips) do
        if b:IsShown() then
            b.FitWidth(0)
            local w = math.min(b:GetWidth(), inner)
            b:SetWidth(w)
            if cx > 0 and cx + w > inner then cx, cy = 0, cy + h + gap end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", page, "TOPLEFT", x + cx, -cy)
            cx = cx + w + gap
        end
    end
    -- Under them, the activity (its word over it), then the roles and the buttons.
    local actLabelY = cy + h + 12
    local actY = actLabelY + 14
    local toolsY = actY + h + 10
    page.actLabel:ClearAllPoints()
    page.actLabel:SetPoint("TOPLEFT", page, "TOPLEFT", x + 2, -actLabelY)
    page.act:SetWidth(math.min(inner, math.max(180, math.floor((inner - gap) / 2))))
    page.act:ClearAllPoints()
    page.act:SetPoint("TOPLEFT", page, "TOPLEFT", x, -actY)
    -- The roles and the three buttons share one row while they fit; when the window is too
    -- narrow the buttons drop to a row of their own under the roles, and the panel grows.
    local rolesW = (page.rolesLabel:GetStringWidth() or 0) + W_.CHIP_GAP * 2
    for _, b in ipairs(page.needs) do
        local tw = b.text:GetStringWidth()
        if type(tw) ~= "number" or tw <= 0 then tw = 40 end
        b:SetWidth(math.floor(tw + 2 * W_.CHIP_PAD + ROLE_ICON + ROLE_GAP + 0.5))
        rolesW = rolesW + b:GetWidth() + W_.CHIP_GAP
    end
    local btnsW = page.refresh:GetWidth() + page.reset:GetWidth() + page.all:GetWidth() + 3 * W_.CHIP_GAP
    local drop = rolesW + btnsW > inner and (W_.CHIP_HEIGHT + W_.CHIP_GAP) or 0
    Browse.below = drop > 0
    local panelH = toolsY + drop + h + Browse.PANEL_PAD - Browse.PANEL_Y
    page.panel:SetHeight(panelH)
    local listTop = Browse.PANEL_Y + panelH + Browse.TOP_GAP
    page.refresh:ClearAllPoints()
    page.refresh:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Browse.EDGE - R.PANEL_IN - room, -(toolsY + drop))
    page.reset:ClearAllPoints()
    page.reset:SetPoint("RIGHT", page.refresh, "LEFT", -W_.CHIP_GAP, 0)
    page.all:ClearAllPoints()
    page.all:SetPoint("RIGHT", page.reset, "LEFT", -W_.CHIP_GAP, 0)
    page.rolesLabel:ClearAllPoints()
    page.rolesLabel:SetPoint("LEFT", page, "TOPLEFT", x + 2, -(toolsY + h / 2))
    local after = page.rolesLabel
    for _, b in ipairs(page.needs) do
        b:ClearAllPoints()
        b:SetPoint("LEFT", after, "RIGHT", after == page.rolesLabel and W_.CHIP_GAP * 2 or W_.CHIP_GAP, 0)
        after = b
    end
    page.stack.scroll:SetPoint("TOPLEFT", page, "TOPLEFT", Win.Parts.EDGE, -listTop)
end

function Browse.PaintChips(page)
    page = page or Browse.page
    local cats = Data().Categories()
    for i, c in ipairs(cats) do
        local b = page.chips[i]
        if not b then
            b = W().Button(page, "", W().CHIP_HEIGHT)
            b:SetScript("OnClick", function(self) Browse.PickCat(self.cat) end)
            page.chips[i] = b
        end
        b.cat = c.id
        b.text:SetText(c.name)
        b.SetActive(c.id == Browse.cat)
        b:Show()
    end
    for i = #cats + 1, #page.chips do page.chips[i]:Hide() end
    layoutBar(page)
    local narrow = not Browse.act and Browse.narrow
    local actName = Browse.act and Data().ActivityName(Browse.act)
    if narrow then
        actName = #narrow == 1 and Data().ActivityName(narrow[1]) or string.format(L["%d activities"], #narrow)
    end
    -- Through SetLabel so the word fades when the pick changes; the button keeps the width the
    -- layout gave it.
    local aw = page.act:GetWidth()
    page.act.SetLabel(actName or L["All activities"])
    page.act:SetWidth(aw)
    page.act.SetActive(actName ~= nil)
    page.act:SetShown(Browse.cat ~= nil)
    page.actLabel:SetShown(Browse.cat ~= nil)
    DUI.Motion.AlphaTo(page.all, (narrow and Browse.cat) and 1 or 0, DUI.Motion.FAST, true)
    page.all.SetOff(Browse.searching == true)
    page.reset.SetOff(Browse.searching == true)
    page.refresh.SetOff(Browse.searching == true or Browse.cat == nil)
    -- Lit when what is set is not what was searched (the level filter changed): searching
    -- again shows the change.
    page.refresh.SetActive(Browse.stale == true)
end

-- A category button picks it and searches it (clicking the lit one refreshes).
function Browse.PickCat(id)
    if id ~= Browse.cat then Browse.act, Browse.narrow, Browse.open = nil, nil, nil end
    Browse.cat = id
    Browse.Search()
end

-- Back to the first category with nothing narrowed, and search it at once.
function Browse.Reset()
    Browse.cat, Browse.act, Browse.narrow = nil, nil, nil
    Browse.need = {}
    for _, b in ipairs(Browse.page and Browse.page.needs or {}) do b.SetActive(false) end
    Browse.Search()
end

function Browse.PickActivity(id)
    if id == Browse.act then return end
    Browse.act, Browse.open = id, nil
    Browse.Render()
end

function Browse.ActivityMenu(owner)
    if not Browse.cat then return end
    local keys, values = { 0 }, { [0] = L["All activities"] }
    for _, g in ipairs(Data().Groups(Browse.cat)) do
        for _, a in ipairs(g.acts) do
            keys[#keys + 1] = a.id
            values[a.id] = a.name
        end
    end
    local narrow = Browse.narrow
    W().OpenMenu(owner, keys, values, Browse.act or (narrow and #narrow == 1 and narrow[1]) or 0,
        function(k) Browse.PickActivity(k ~= 0 and k or nil) end, owner:GetWidth())
end

-- The list

local acts = {}
function acts.whisper(r) Data().Whisper(r.leader.name) end
function acts.invite(r) Data().Invite(r.leader.name) end
function acts.edit() if ns.Window then ns.Window.ShowTab("list") end end
function acts.unlist() if ns.Listing then ns.Listing.Unlist() end end

-- Does a listing pass the role filter: a group with an open spot for one of the roles asked
-- for, a player listed alone who can be one of them.
local function wanted(r)
    if next(Browse.need) == nil or r.mine then return true end
    if r.solo then
        local can = r.roles or {}
        for role in pairs(Browse.need) do if can[Data().ROLE_KEY[role]] then return true end end
        return false
    end
    local _, open = Data().Places(r)
    for role in pairs(Browse.need) do if (open[role] or 0) > 0 then return true end end
    return false
end

local function rowOf(s, r)
    local who = ns.Rows.Named(r.leader.name, r.leader.class)
    local sub = who
    local hex = Win.Parts.Hex
    if type(r.leader.level) == "number" then sub = sub .. "  " .. hex({ Style.Accent() }) .. r.leader.level .. "|r" end
    if r.leader.zone then sub = sub .. "  ·  " .. hex(Style.INK.WARN) .. r.leader.zone .. "|r" end
    if r.style then sub = sub .. "  ·  " .. hex(r.styleInk or Style.INK.LABEL) .. r.style .. "|r" end
    return ns.Rows.Row(s, { kind = "group", height = r.note and ns.Rows.GROUP_NOTE or ns.Rows.GROUP, result = r, sep = true,
        text = r.mine and (L["Your listing"] .. ": " .. r.text) or r.text,
        color = Style.INK.VALUE, icon = ns.Rows.ClassIcon(r.leader.class),
        sub = sub, note = r.note and (Win.Parts.Hex(Style.INK.LABEL) .. (LABEL_NOTE or L["Note"]) .. ":|r " .. r.note) or nil,
        roles = ns.Rows.Badges(r), age = ns.Rows.Age(r.age), dim = r.delisted,
        picked = Browse.open == r.id,
        onEnter = function(b) ns.Rows.Tip(b, r) end,
        onClick = function() Browse.Toggle(r.id) end,
        onMenu = function(b) if not r.mine then ns.Rows.Menu(b, r.leader.name, Data().CanInvite(r)) end end })
end

-- What the card shows for a listing: its leader, the activity, where and how they play,
-- the note, who is in and what is still open, and only the buttons that apply (Invite for
-- a player listed alone when the game would allow it; Edit and Unlist for your own).
function Browse.Spec(r)
    local ink = Style.INK
    local hex = Win.Parts.Hex
    local rows = {}
    local function add(label, value, color, lines)
        if value == nil or value == "" then return nil end
        local row = { label = label, value = tostring(value), color = color, lines = lines }
        rows[#rows + 1] = row
        return row
    end
    if r.delisted then add(nil, L["No longer listed"], ink.WARN) end
    if r.newcomers then add(nil, L["New players welcome"], ink.GOOD) end
    add(L["Activity"], r.text, nil, 3)
    add(LEVEL or L["Level"], r.leader.level)
    add(L["Zone"], r.leader.zone)
    add(GROUP_FINDER_FILTER_PLAYSTYLE or L["Playstyle"], r.style, r.styleInk)
    add(LABEL_NOTE or L["Note"], r.note)
    -- Who is in, one to a line (a role badge, the name, the level), the open spots after them
    -- as rings of the role; a player listed alone shows the roles they can be.
    local people = {}
    if r.solo then
        for _, item in ipairs(ns.Rows.Badges(r)) do
            people[#people + 1] = { role = item.role, name = ns.Listing.ROLE_WORD[item.role]() }
        end
        if #people > 0 then rows[#rows + 1] = { label = L["Can be"], people = people } end
    elseif r.size > ns.Rows.MEMBERS then
        local text, of = ns.Rows.Counts(r)
        add(L["In the group"], text .. "   " .. of, nil, 2)
    else
        for _, m in ipairs(r.members) do
            people[#people + 1] = { role = m.role, name = ns.Rows.Named(m.name, m.class), level = m.level }
        end
        local _, open = Data().Places(r)
        for _, role in ipairs(Data().ROLES) do
            for _ = 1, open[role] do people[#people + 1] = { role = role, open = true, name = L["Open spot"] } end
        end
        if #people > 0 then rows[#rows + 1] = { label = L["In the group"], people = people } end
    end
    local buttons = {}
    if r.mine then
        buttons[1] = { text = L["Edit listing"], primary = true, off = not Data().CanEdit(), onClick = acts.edit }
        buttons[2] = { text = L["Unlist"], off = not Data().CanEdit(), onClick = acts.unlist }
    elseif type(r.leader.name) == "string" then
        local can = Data().CanInvite(r)
        if can then buttons[#buttons + 1] = { text = INVITE or L["Invite"], primary = true, onClick = function() acts.invite(r) end } end
        buttons[#buttons + 1] = { text = WHISPER or L["Whisper"], primary = not can, onClick = function() acts.whisper(r) end }
    end
    local icon
    if r.leader.class and DUI.ClassIcon then icon = { DUI.ClassIcon(r.leader.class) } end
    local red, green, blue = 1, 1, 1
    if r.leader.class then red, green, blue = Style.ClassTextColor(r.leader.class) end
    local sub = {}
    if r.leader.class then sub[#sub + 1] = ns.Rows.ClassWord(r.leader.class) end
    local age = ns.Rows.Age(r.age)
    if age ~= "" then sub[#sub + 1] = age end
    return { icon = icon, initial = r.leader.name, title = r.leader.name or r.text, color = { red, green, blue },
        sub = table.concat(sub, "  ·  "), rows = rows, buttons = buttons }
end

function Browse.PaintDetail()
    local page = Browse.page
    if not (page and page.detail) then return end
    local r = Browse.open and Browse.shown and Browse.shown[Browse.open]
    local changed = page.detail:Set(r and Browse.Spec(r) or nil)
    if ns.Window.PadChanged then ns.Window.PadChanged() end   -- the controller's X follows the card's button
    return changed
end

-- The card open or closed: Refresh keeps to the list's side, and the list's right edge
-- moves off the card.
function Browse.Fit(page, p)
    local room = ns.Window.Span() * p
    Browse.room = room
    page.refresh:ClearAllPoints()
    layoutBar(page)
    page.stack.scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -page.stack.side - room, Card().REST)
end

-- keep: keep the scroll (a refill).
function Browse.Render(page, keep)
    page = page or Browse.page
    if not page then return end
    Browse.PaintChips(page)
    local s = page.stack
    local at = keep and s:Scrolled() or 0
    s:Begin()
    Browse.shown, Browse.rowList = {}, {}
    local list = Browse.searching and {} or (Browse.results or {})
    local mine, groups, solo = {}, {}, {}
    -- Delisted: the last search still includes the player's listing until the next one.
    local listed = Data().Entry() ~= nil
    for _, r in ipairs(list) do
        if Browse.act and not tContains(r.acts, Browse.act) then
            -- not the selected activity
        elseif not wanted(r) then
            -- not a role asked for
        elseif r.mine and not listed then
            if Browse.open == r.id then Browse.open = nil end
        elseif r.mine then mine[#mine + 1] = r elseif r.solo then solo[#solo + 1] = r else groups[#groups + 1] = r end
    end
    local function put(r)
        Browse.shown[r.id] = r
        Browse.rowList[#Browse.rowList + 1] = rowOf(s, r)
    end
    for _, r in ipairs(mine) do put(r) end
    local inGroup = IsInGroup and IsInGroup() == true
    local parts = inGroup and { { L["Solo players"], solo }, { L["Groups"], groups } } or { { L["Groups"], groups }, { L["Solo players"], solo } }
    -- A wide window shows the two lists side by side instead of one long column.
    Browse.both = #groups > 0 and #solo > 0
    local split = Browse.both and s:Width() >= Browse.SPLIT_W
    Browse.split = split
    for i, p in ipairs(parts) do
        if #p[2] > 0 then
            if split then s:Column(i) end
            s:Section(p[1] .. "  " .. #p[2])
            for _, r in ipairs(p[2]) do put(r) end
        end
    end
    page.pieces = s:End()
    if Browse.fresh then Win.Feel.Stagger(page.pieces, 0) end
    Browse.fresh = nil
    if Browse.open and not Browse.shown[Browse.open] then Browse.open = nil end
    -- Nothing to show: explain why, in the label color.
    local note
    if Browse.searching then note = L["Searching..."]
    elseif Browse.failed then note = L["The search failed. Try Refresh."]
    elseif not Browse.cat then note = L["Nothing to find at your level yet."]
    elseif #mine + #groups + #solo == 0 and Browse.searched then note = L["No groups match."]
    elseif #list == 0 then note = L["Pick a category to look for groups."] end
    page.note:SetText(note or "")
    page.note:SetShown(note ~= nil)
    Browse.Seek(page, Browse.searching == true)
    s:ScrollTo(at)
    Browse.PaintDetail()
end

-- While the grip is dragged: the rows only stretch, unless the list just got wide or
-- narrow enough to change its columns, which needs one refill right then.
function Browse.Stretch(page)
    page = page or Browse.page
    if not page then return end
    local split = Browse.both == true and page.stack:Width() >= Browse.SPLIT_W
    if split ~= (Browse.split == true) then Browse.Render(page, true) else page.stack:Stretch() end
end

-- Searching bar: fills repeatedly while a search is pending.
function Browse.Seek(page, on)
    local bar = page.seek
    bar:SetShown(on)
    if not on then return end
    local M = DUI.Motion
    if not (M and M.On()) then bar:SetValue(1); return end
    local function loop()
        if not (Browse.searching and bar:IsVisible()) then return end
        M.Tween(bar, 0, 1, Browse.SEEK, function(v) bar:SetValue(v) end, loop)
    end
    loop()
end

-- Click on a listing: pick it (and open the card), or close the card when it is the picked one.
function Browse.Toggle(id)
    Browse.open = (Browse.open ~= id) and id or nil
    for _, b in ipairs(Browse.rowList or {}) do ns.Rows.Pick(b, b.spec.result.id == Browse.open) end
    Browse.PaintDetail()
end

-- The page

function Browse.Build(page)
    Browse.page = page
    page.panel = ns.Rows.Panel(page)
    -- Its width is set by the bar's layout.
    local function dropdown(onClick)
        local b = W().MenuButton(page, "", W().CHIP_HEIGHT)
        b.text:SetPoint("RIGHT", b.chevron, "LEFT", -6, 0)
        b.text:SetWordWrap(false)
        b:SetScript("OnClick", onClick)
        return b
    end
    local function word(text)
        local fs = Style.Text(page, Style.SIZE.small, "LEFT")
        fs:SetText(text)
        Style.InkText(fs, "LABEL")
        return fs
    end
    page.catLabel = word(Browse.CatWord())
    page.chips = {}   -- one button per category, made as they are first shown
    page.actLabel = word(Browse.ActWord())
    page.rolesLabel = word(_G.ROLES or L["Roles"])
    page.act = dropdown(function(self) Browse.ActivityMenu(self) end)
    page.refresh = W().Button(page, REFRESH or L["Refresh"], W().CHIP_HEIGHT)
    page.refresh.FitWidth(80)
    page.refresh:SetScript("OnClick", function() Browse.Refresh() end)
    page.reset = W().Button(page, _G.RESET or L["Reset"], W().CHIP_HEIGHT)
    page.reset.FitWidth(80)
    page.reset:SetScript("OnClick", function() Browse.Reset() end)
    page.all = W().Button(page, L["Show all"], W().CHIP_HEIGHT)
    page.all.FitWidth(0)
    page.all:SetScript("OnClick", function() Browse.ShowAll() end)
    page.all:Hide()
    -- The buttons and the drop-down follow the window while it is dragged.
    page:HookScript("OnSizeChanged", function(self, width) layoutBar(self, width) end)
    -- Role buttons, each with its badge and its word as on List yourself: show only the
    -- groups that still want a tank, a healer or damage (any of those lit), or the
    -- players who offer it.
    page.needs = {}
    for i, role in ipairs(Data().ROLES) do
        local b = W().Button(page, "", W().CHIP_HEIGHT)
        b.icon = W().Role(b, ROLE_ICON)
        b.icon:SetPoint("LEFT", b, "LEFT", W().CHIP_PAD, 0)
        b.icon.Set(role)
        b.text:SetText(ns.Listing.ROLE_WORD[role]())
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", b.icon, "RIGHT", ROLE_GAP, 0)
        b.text:SetJustifyH("LEFT")
        b.role = role
        b:SetScript("OnClick", function(self)
            Browse.need[role] = (not Browse.need[role]) or nil
            self.SetActive(Browse.need[role] == true)
            Browse.Render(nil, true)
        end)
        b:HookScript("OnEnter", function(self)
            W().Tooltip(self, ns.Listing.ROLE_WORD[role](), L["Groups with an open spot for this role, and solo players who can play it."])
        end)
        b:HookScript("OnLeave", function() W().HideTooltip() end)
        page.needs[i] = b
    end
    page.stack = Win.Parts.Stack(page, { top = Browse.TOP, bottom = Card().REST })
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", page, "CENTER", 0, 10)
    Style.InkText(page.note, "LABEL")
    page.note:Hide()
    page.seek = W().Bar(page, W().BAR_H)
    page.seek:SetWidth(Browse.SEEK_W)
    page.seek:SetPoint("TOP", page.note, "BOTTOM", 0, -10)
    page.seek:SetMinMaxValues(0, 1)
    W().BarAccent(page.seek)
    page.seek:Hide()
    page.detail = Card().New(page, { refill = function() Browse.Render(nil, true) end,
        side = function(open) ns.Window.SetSide("find", open) end, fit = function(p) Browse.Fit(page, p) end })
    for _, e in ipairs(Browse.EVENTS) do
        DUI.RegisterEvent(e, function(event)
            if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then received(false)
            elseif event == "LFG_LIST_SEARCH_FAILED" then received(true)
            elseif event == "LFG_LIST_AVAILABILITY_UPDATE" then Data().Forget(); Browse.Soon()
            else Browse.Soon() end
        end)
    end
end

-- On show: the last search's results (the game's or this window's). A search needs a
-- click or key (C_LFGList.Search, like the game's Refresh), so opening the window never
-- searches; a tab click does (Window.ShowTab).
function Browse.Fill(page)
    page = page or Browse.page
    Browse.cat = Browse.PickCategory()
    if not Browse.searching then Browse.results = Data().Results() end
    if #(Browse.results or {}) > 0 then Browse.searched = true end
    -- Listed at login: the game's page searched the listing's activities
    -- (LFGBrowseMixin:OnLoad), not the whole category.
    if not Browse.ours and not Browse.narrow and Browse.searched then
        local e = Data().Entry()
        Browse.narrow = plainIDs(e and e.activityIDs)
    end
    Browse.Render(page)
end

-- Lift-in order: chips, then visible rows.
function Browse.Pieces(page)
    local out = {}
    out[#out + 1] = page.panel
    for _, b in ipairs(page.chips) do
        if b:IsShown() then out[#out + 1] = b end
    end
    out[#out + 1] = page.act
    out[#out + 1] = page.rolesLabel
    for _, b in ipairs(page.needs) do out[#out + 1] = b end
    if page.all:IsShown() then out[#out + 1] = page.all end
    out[#out + 1] = page.reset
    out[#out + 1] = page.refresh
    for i, p in ipairs(page.pieces or {}) do
        if i > 10 then break end
        out[#out + 1] = p
    end
    return out
end
