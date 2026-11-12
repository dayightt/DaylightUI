-- Find a group: category buttons and an activity button with Refresh on top, then the
-- last search's listings in the game's order. The player's own first, then groups and
-- solo players (reversed while in a group). Hovering a listing shows the whole party in
-- a tooltip. Clicking opens it in place (note, members, open spots, Whisper, Invite)
-- and the rows below glide down. Right-click gives Whisper / Invite at the cursor.
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
Browse.CHIPS_Y = 10
Browse.TOOLS_Y = 42
Browse.TOP = 76
Browse.SEEK = 0.8        -- s for the searching bar to fill, repeated
Browse.SEEK_W = 140
Browse.WAIT = 3          -- s to wait for the game's own search first
Browse.EVENTS = { "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_FAILED", "LFG_LIST_SEARCH_RESULT_UPDATED",
    "LFG_LIST_AVAILABILITY_UPDATE", "GROUP_ROSTER_UPDATE", "LFG_LIST_ACTIVE_ENTRY_UPDATE" }

local function W() return DUI.Widgets end
local function Data() return ns.Data end

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
function Browse.Search(only)
    local cat = Browse.PickCategory()
    Browse.cat = cat
    if not cat then return Browse.Render() end
    local acts = only or Data().Filtered(cat)
    Browse.searching, Browse.failed, Browse.open = true, false, nil
    Browse.searched, Browse.ours, Browse.narrow = true, true, only
    Data().Ask("Search", cat, 0, 0, nil, false, nil, acts)
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

local function received(failed)
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

-- Chips: categories, activity, Refresh

-- Page width (the target width while the window is resizing).
function Browse.Width(page)
    return page.stack:Width() + 2 * Win.Parts.EDGE
end

-- Category buttons wrap to another row when out of room (long French names), like List
-- yourself. The activity row and list sit under however many rows that takes.
local function layoutChips(page)
    local W_ = W()
    local x, y = Browse.EDGE, Browse.CHIPS_Y
    local right = Browse.Width(page) - Browse.EDGE
    for _, b in ipairs(page.chips) do
        if b:IsShown() then
            b.FitWidth(0)
            local w = b:GetWidth()
            if x > Browse.EDGE and x + w > right then
                x, y = Browse.EDGE, y + W_.CHIP_HEIGHT + W_.CHIP_GAP
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
            x = x + w + W_.CHIP_GAP
        end
    end
    local down = y - Browse.CHIPS_Y
    page.act:ClearAllPoints()
    page.act:SetPoint("TOPLEFT", page, "TOPLEFT", Browse.EDGE, -(Browse.TOOLS_Y + down))
    page.refresh:ClearAllPoints()
    page.refresh:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Browse.EDGE, -(Browse.TOOLS_Y + down))
    page.stack.scroll:SetPoint("TOPLEFT", page, "TOPLEFT", Win.Parts.EDGE, -(Browse.TOP + down))
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
    layoutChips(page)
    local narrow = not Browse.act and Browse.narrow
    local name = Browse.act and Data().ActivityName(Browse.act)
    if narrow then
        name = #narrow == 1 and Data().ActivityName(narrow[1]) or string.format(L["%d activities"], #narrow)
    end
    page.act.text:SetText(name or L["All activities"])
    page.act.FitWidth(0)
    page.act.SetActive(name ~= nil)
    page.act:SetShown(Browse.cat ~= nil)
    DUI.Motion.AlphaTo(page.all, (narrow and Browse.cat) and 1 or 0, DUI.Motion.FAST, true)
    page.all.SetOff(Browse.searching == true)
    page.refresh.SetOff(Browse.searching == true or Browse.cat == nil)
end

-- Category chip: search that category (clicking the lit one refreshes).
function Browse.PickCat(id)
    if id ~= Browse.cat then Browse.act = nil end
    Browse.cat = id
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
    W().OpenMenu(owner, keys, values, Browse.act or (narrow and #narrow == 1 and narrow[1]) or 0, function(k) Browse.PickActivity(k ~= 0 and k or nil) end, 180)
end

-- The list

local acts = {}
function acts.whisper(r) Data().Whisper(r.leader.name) end
function acts.invite(r) Data().Invite(r.leader.name) end
function acts.edit() if ns.Window then ns.Window.ShowTab("list") end end
function acts.unlist() if ns.Listing then ns.Listing.Unlist() end end

local function rowOf(s, r)
    local who = ns.Rows.Named(r.leader.name, r.leader.class)
    local sub = who
    local hex = Win.Parts.Hex
    if type(r.leader.level) == "number" then sub = sub .. "  " .. hex({ Style.Accent() }) .. r.leader.level .. "|r" end
    if r.leader.zone then sub = sub .. "  ·  " .. hex(Style.INK.WARN) .. r.leader.zone .. "|r" end
    if r.style then sub = sub .. "  ·  " .. hex(r.styleInk or Style.INK.LABEL) .. r.style .. "|r" end
    return ns.Rows.Row(s, { kind = "group", height = r.note and ns.Rows.GROUP_NOTE or ns.Rows.GROUP, result = r,
        text = r.mine and (L["Your listing"] .. ": " .. r.text) or r.text,
        color = Style.INK.VALUE,
        sub = sub, note = r.note, roles = ns.Rows.Badges(r), age = ns.Rows.Age(r.age), dim = r.delisted,
        picked = Browse.open == r.id,
        onEnter = function(b) ns.Rows.Tip(b, r) end,
        onClick = function() Browse.Toggle(r.id) end,
        onMenu = function(b) if not r.mine then ns.Rows.Menu(b, r.leader.name, Data().CanInvite(r)) end end })
end

-- keep: keep the scroll (a refill); glide: the opened group glides open.
function Browse.Render(page, keep, glide)
    page = page or Browse.page
    if not page then return end
    local after = Browse.StopGlide()
    Browse.PaintChips(page)
    local s = page.stack
    local at = keep and s:Scrolled() or 0
    s:Begin()
    local opened
    local list = Browse.searching and {} or (Browse.results or {})
    local mine, groups, solo = {}, {}, {}
    -- Delisted: the last search still includes the player's listing until the next one.
    local listed = Data().Entry() ~= nil
    for _, r in ipairs(list) do
        if Browse.act and not tContains(r.acts, Browse.act) then
            -- not the selected activity
        elseif r.mine and not listed then
            if Browse.open == r.id then Browse.open = nil end
        elseif r.mine then mine[#mine + 1] = r elseif r.solo then solo[#solo + 1] = r else groups[#groups + 1] = r end
    end
    local function put(r)
        rowOf(s, r)
        if Browse.open == r.id then opened = ns.Rows.Opened(s, r, acts) end
    end
    for _, r in ipairs(mine) do put(r) end
    local inGroup = IsInGroup and IsInGroup() == true
    local parts = inGroup and { { L["Solo players"], solo }, { L["Groups"], groups } } or { { L["Groups"], groups }, { L["Solo players"], solo } }
    for _, p in ipairs(parts) do
        if #p[2] > 0 then
            s:Section(p[1] .. "  " .. #p[2])
            for _, r in ipairs(p[2]) do put(r) end
        end
    end
    page.pieces = s:End()
    if Browse.fresh then Win.Feel.Stagger(page.pieces, 0) end
    Browse.fresh = nil
    Browse.opened = opened
    -- Nothing to show: explain why, in the label color.
    local note
    if Browse.searching then note = L["Searching..."]
    elseif Browse.failed then note = L["The search failed. Try Refresh."]
    elseif not Browse.cat then note = L["Nothing to find at your level yet."]
    elseif #list == 0 and Browse.searched then note = L["No groups match."]
    elseif #list == 0 then note = L["Pick a category to look for groups."] end
    page.note:SetText(note or "")
    page.note:SetShown(note ~= nil)
    Browse.Seek(page, Browse.searching == true)
    s:ScrollTo(at)
    if glide and opened then Browse.Glide(s, opened, true) end
    -- A glide cut short still finishes its job (closing one opens the next) once this list is drawn.
    if after then after() end
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

-- The opened group glides open (or closed): its height grows from zero and the rows
-- below slide down with it.
function Browse.Glide(s, d, opening, done)
    local followers, after = {}, false
    for _, p in ipairs(s.pieces) do
        if after then
            local _, _, _, _, y = p:GetPoint(1)
            followers[#followers + 1] = { p, type(y) == "number" and y or 0 }
        elseif p == d then
            after = true
        end
    end
    local full = d.full or d:GetHeight() or 0
    local function step(t)
        d:SetHeight(math.max(0.01, full * t))
        for _, f in ipairs(followers) do
            f[1]:ClearAllPoints()
            f[1]:SetPoint("TOPLEFT", s.child, "TOPLEFT", 0, f[2] + (1 - t) * full)
        end
    end
    local M = DUI.Motion
    if M then
        Browse.gliding, Browse.glideDone = d, done
        M.Tween(d, opening and 0 or 1, opening and 1 or 0, M.NORMAL, step, function()
            Browse.gliding, Browse.glideDone = nil, nil
            if done then done() end
        end)
    else
        step(opening and 1 or 0)
        if done then done() end
    end
end

-- The list was redrawn, so stop any glide where it is (its rows are pooled stack
-- pieces that just got placed again; Parts.Light stops an ease the same way).
-- Returns the glide's end action for the caller to run.
function Browse.StopGlide()
    local d, done = Browse.gliding, Browse.glideDone
    Browse.gliding, Browse.glideDone = nil, nil
    if d and DUI.Motion then DUI.Motion.Tween(d, 0, 0, 0) end
    return done
end

-- Click on a listing: open it (closing any other first), or close it.
function Browse.Toggle(id)
    local s = Browse.page and Browse.page.stack
    if not s then return end
    local was = Browse.open
    Browse.glideDone = nil   -- this click is the newest; drop any earlier pending open
    local function openNew()
        Browse.open = (was ~= id) and id or nil
        Browse.Render(nil, true, Browse.open ~= nil)
    end
    if was and Browse.opened then
        Browse.open = nil
        if was == id then
            return Browse.Glide(s, Browse.opened, false, function() Browse.Render(nil, true) end)
        end
        return Browse.Glide(s, Browse.opened, false, openNew)
    end
    openNew()
end

-- The page

function Browse.Build(page)
    Browse.page = page
    page.chips = {}
    page.act = W().Button(page, L["All activities"], W().CHIP_HEIGHT)
    page.act:SetScript("OnClick", function(self) Browse.ActivityMenu(self) end)
    page.all = W().Button(page, L["Show all"], W().CHIP_HEIGHT)
    page.all.FitWidth(0)
    page.all:SetPoint("LEFT", page.act, "RIGHT", W().CHIP_GAP, 0)
    page.all:SetScript("OnClick", function() Browse.ShowAll() end)
    page.all:Hide()
    page.refresh = W().Button(page, REFRESH or L["Refresh"], W().CHIP_HEIGHT)
    page.refresh.FitWidth(80)
    page.refresh:SetScript("OnClick", function() Browse.Refresh() end)
    page.stack = Win.Parts.Stack(page, { top = Browse.TOP, bottom = 12 })
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
    for _, b in ipairs(page.chips) do if b:IsShown() then out[#out + 1] = b end end
    out[#out + 1] = page.act
    if page.all:IsShown() then out[#out + 1] = page.all end
    out[#out + 1] = page.refresh
    for i, p in ipairs(page.pieces or {}) do
        if i > 10 then break end
        out[#out + 1] = p
    end
    return out
end
