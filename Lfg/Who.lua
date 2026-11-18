-- Who page: a search box (the game's /who syntax: name, zone, class, guild, level or a
-- range like "20-25"), drop-downs to tick any number of races, classes and zones (the game's
-- own lists; they go in the /who text, one term for each pick) and a Sort by drop-down (name, class, level via
-- C_FriendList.SortWho), Search and Reset, how many the server found, then the results: name in class color with guild, level, race
-- and class below and zone on the right. Click picks one and opens a detail card beside
-- the list (Social's, DUI.Social.Detail) with what is known of them and Whisper and
-- Invite; click again to close it. Right-click offers the same at the cursor. Who results are routed to this page
-- only while it shows (C_FriendList.SetWhoToUi, which is one client-wide switch; the
-- game's page does the same).

local _, DUI = ...
DUI.Lfg = DUI.Lfg or {}
local ns = DUI.Lfg
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Who = {}
ns.Who = Who

Who.EDGE = 16
Who.PANEL_Y = 10         -- the filters' panel
Who.SEARCH_Y = 22        -- the search box
Who.LABEL_Y = 56         -- the small words over each drop-down
Who.DROP_Y = 70          -- the drop-downs' row
Who.BUTTON_Y = 106       -- Search and Reset when they drop under the drop-downs (a narrow window)
Who.PANEL_H = 136
Who.FOUND_Y = 158        -- "50 found"
Who.TOP = 186
Who.LIFT = 36            -- what the panel loses when Search and Reset sit beside the drop-downs
Who.DROP_MIN = 120       -- narrower than this and the buttons drop under the row
Who.SORTS = { "level", "name", "class" }   -- the game's WHO_SORT_* keys
Who.WAIT = 6        -- s without an answer before the search counts as lost
Who.COOL = 3        -- s we wait between two /who, until the game says how long it wants
Who.MARGIN = 0.3    -- s added to what the game says
Who.SEEK, Who.SEEK_W = 0.8, 140

local function W() return DUI.Widgets end
local function Card() return DUI.Social.Detail end
local function Data() return ns.Data end

local function friends() return type(C_FriendList) == "table" and C_FriendList or nil end

-- The filters: any number of races, classes and zones, as the game's own who filter lets you
-- tick. They go in the /who text, one term for each pick, so the server's 50 are all of that kind. Each is a set of the game's ids (Who.races[2] = true).
Who.races, Who.classes, Who.zones = {}, {}, {}

-- The three filters: the drop-down's key and the set it edits.
Who.FILTERS = { { "race", "races", "raceIDs" }, { "class", "classes", "classIDs" }, { "zone", "zones", "uiMapIDs" } }

local function ids(set)
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out
end

function Who.Picked(key)
    for _, f in ipairs(Who.FILTERS) do
        if f[1] == key then return next(Who[f[2]]) ~= nil end
    end
end

-- The picked filters as /who terms, the same one repeated for each pick (r-"Dwarf" r-"Human"
-- asks for either): the game's server takes them in the text; SendWho's own filter lists are
-- ignored (checked in game).
function Who.Terms()
    local out = {}
    local sources = { race = Who.Races, class = Who.Classes, zone = function() return Who.ZoneTree().all end }
    local letter = { race = "r", class = "c", zone = "z" }
    for _, f in ipairs(Who.FILTERS) do
        local set = Who[f[2]]
        if next(set) ~= nil then
            for _, it in ipairs(sources[f[1]]()) do
                if set[it[1]] then out[#out + 1] = letter[f[1]] .. '-"' .. it[2]:gsub('"', "") .. '"' end
            end
        end
    end
    return out
end

function Who.Query(text)
    text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
    local parts = Who.Terms()
    if text ~= "" then table.insert(parts, 1, text) end
    if #parts == 0 then return tostring(Data().Level()) end
    return table.concat(parts, " ")
end

function Who.AnyFilter()
    for _, f in ipairs(Who.FILTERS) do
        if next(Who[f[2]]) ~= nil then return true end
    end
    return false
end

-- What a search asks, as one line: the text and the picked ids. Search is lit while this is not
-- what was last asked.
function Who.Signature(text)
    local parts = { Who.Query(text) }
    for _, f in ipairs(Who.FILTERS) do parts[#parts + 1] = table.concat(ids(Who[f[2]]), ",") end
    return table.concat(parts, "|")
end

-- A /who from the search box (Enter), a filter or a tab click. Empty search with no
-- filter = everyone at the player's level.
function Who.Send(text)
    local F = friends()
    if not (F and F.SendWho) then return end
    -- The game answers one /who in two seconds. The controls that ask are off for that
    -- long, so this is only a guard (Enter in the box).
    if Who.Cooling() then return false end
    local signature = Who.Signature(text)
    text = Who.Query(text)
    Who.asked, Who.askedText = signature, text
    Who.searching, Who.failed = true, false
    Who.sentAt = GetTime()
    Who.coolUntil = Who.sentAt + Who.COOL
    Who.waitMsg = nil
    Who.token = (Who.token or 0) + 1
    local mine = Who.token
    local origin = Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social
    pcall(F.SendWho, text, origin)
    C_Timer.After(Who.COOL, function() Who.Render() end)
    -- The game may let nothing through (a search it refused leaves no answer): stop waiting.
    C_Timer.After(Who.WAIT, function()
        if Who.token == mine and Who.searching then
            Who.searching, Who.failed = false, true
            Who.Render()
        end
    end)
    Who.Render()
end

-- The game turned the search down with WHO_COOLDOWN ("You must wait %d s. before using /who
-- again", a red error line, in the player's language). Only that line counts: its pattern
-- is made from the game's own sentence, so another error with a number in it is not ours.
function Who.WaitPattern()
    local fmt = _G.WHO_COOLDOWN
    if type(fmt) ~= "string" or fmt == "" then fmt = "You must wait %d s. before using /who again." end
    -- The %d aside, the rest escaped so its punctuation is only text, then the %d takes its place.
    local pattern = fmt:gsub("%%d", ""):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("", "(%%d+)")
    return "^" .. pattern .. "$"
end

-- Take its N and how long ago we asked as the real wait, show the game's own sentence, and
-- keep the controls off until it is up.
function Who.Refused(message)
    if not (Who.searching and Who.sentAt) or type(message) ~= "string" then return false end
    local n = tonumber(message:match(Who.WaitPattern()))
    local since = GetTime() - Who.sentAt
    if not n or since > 2 then return false end
    Who.COOL = math.max(Who.COOL, since + n + Who.MARGIN)   -- learned: the next ones wait long enough
    Who.coolUntil = GetTime() + n + Who.MARGIN
    Who.searching, Who.failed, Who.waitMsg = false, false, message
    C_Timer.After(n + Who.MARGIN, function() Who.Render() end)
    Who.Render()
    return true
end

function Who.Cooling()
    return GetTime() < (Who.coolUntil or 0)
end

-- Filters off and the box empty. It asks nothing: Search then asks for everyone at your level.
function Who.Reset()
    Who.races, Who.classes, Who.zones = {}, {}, {}
    local page = Who.page
    if page then page.search:SetText("") end
    Who.Changed()
end

function Who.Filtered()
    local page = Who.page
    return Who.AnyFilter() or (page ~= nil and (page.search:GetText() or "") ~= "")
end

-- The answer in the order the Sort by drop-down says (the game hands it over by zone): level
-- low to high, name or class A to Z, ties by name. A copy; the game's list is left alone.
function Who.Sorted(list)
    local mode = Who.sort or "level"
    local out = {}
    for i, p in ipairs(list) do out[i] = p end
    local function key(p)
        if mode == "level" then return tonumber(p.level) or 0 end
        if mode == "class" then return (p.class or ""):lower() end
        return (p.name or ""):lower()
    end
    table.sort(out, function(a, b)
        local x, y = key(a), key(b)
        if x ~= y then return x < y end
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    return out
end

function Who.Sort(mode)
    Who.sort = mode
    local F = friends()
    if F and F.SortWho then pcall(F.SortWho, mode) end
    Who.Render()
end

local function everyone() return _G.ALL or L["All"] end

-- A drop-down's word, through its SetLabel so it fades when the pick changes. The button keeps
-- the width the layout gave it (SetLabel would size it to the word).
local function say(b, words)
    local w = b:GetWidth()
    b.SetLabel(words)
    b:SetWidth(w)
end

-- A drop-down's words: everyone when nothing is ticked, the name when one is, the first and how
-- many more when several. items are { id, name }.
function Who.Summary(set, items)
    local names = {}
    for _, it in ipairs(items) do if set[it[1]] then names[#names + 1] = it[2] end end
    if #names == 0 then return everyone() end
    if #names == 1 then return names[1] end
    return names[1] .. " +" .. (#names - 1)
end

local CHECK_ALL = function() return _G.CHECK_ALL or L["Check All"] end
local UNCHECK_ALL = function() return _G.UNCHECK_ALL or L["Uncheck All"] end

-- A menu of ticks, as the game's own filter has: Check All and Uncheck All first, then the choices
-- (each ticks or unticks and the menu stays open). items are { id, name }; extra adds rows (the
-- continents) with their own names and what a click on them does.
local function ticks(owner, items, set, extra)
    local keys, values, titles = { "all", "none" }, { all = CHECK_ALL(), none = UNCHECK_ALL() }, {}
    local more, doing = {}, {}
    local function add(key, name) keys[#keys + 1] = key; values[key] = name end
    if extra and extra.title then
        table.insert(keys, 1, "title"); values.title = extra.title; titles.title = true
    end
    for _, it in ipairs(items) do add(it[1], it[2]) end
    if extra then
        for _, row in ipairs(extra.rows or {}) do
            add(row.key, row.name); more[row.key] = true; doing[row.key] = row.open
        end
        if extra.back then add("back", "‹ " .. (_G.BACK or L["Back"])); doing.back = extra.back end
    end
    local function scope() return (extra and extra.scope) or items end
    W().OpenMenu(owner, keys, values, nil, function(key)
        if doing[key] then return doing[key]() end
        if key == "all" then for _, it in ipairs(scope()) do set[it[1]] = true end
        elseif key == "none" then for _, it in ipairs(scope()) do set[it[1]] = nil end
        else set[key] = (not set[key]) or nil end
        Who.Changed()
    end, 190, { rows = 12, keepOpen = true, titles = titles, more = more,
        checked = function(key) return set[key] == true end })
end

-- The races of this client, as the game's own filter lists them (C_FriendList.GetWhoRaceFilters).
function Who.Races()
    local out = {}
    local F = friends()
    local ok, filters = false, nil
    if F and F.GetWhoRaceFilters then ok, filters = pcall(F.GetWhoRaceFilters) end
    if ok and type(filters) == "table" then
        for _, f in ipairs(filters) do
            if type(f) == "table" and type(f.name) == "string" and type(f.ID) == "number" then out[#out + 1] = { f.ID, f.name } end
        end
    end
    table.sort(out, function(a, b) return a[2] < b[2] end)
    return out
end

-- The classes of this client: the game's class ids until one is missing.
function Who.Classes()
    local out = {}
    local info = (C_CreatureInfo and C_CreatureInfo.GetClassInfo) or (C_ClassInfo and C_ClassInfo.GetClassInfo)
    if info then
        for id = 1, 30 do
            local ok, c = pcall(info, id)
            if ok and type(c) == "table" and type(c.className) == "string" then out[#out + 1] = { c.classID or id, c.className } end
        end
    end
    table.sort(out, function(a, b) return a[2] < b[2] end)
    return out
end

-- The zones, as the game's world map has them: the continents, each with its zones, and any zone
-- hung straight off the world (Zephras). Built once: { loose = { { id, name } }, groups = { { id,
-- name, zones } }, all = { { id, name } } }.
function Who.ZoneTree()
    if Who.tree and #Who.tree.all > 0 then return Who.tree end
    local tree = { loose = {}, groups = {}, all = {} }
    local M = C_Map
    local T = Enum and Enum.UIMapType or { World = 1, Continent = 2, Zone = 3 }
    local function children(id, kind, deep)
        if not (M and M.GetMapChildrenInfo) then return {} end
        local ok, list = pcall(M.GetMapChildrenInfo, id, kind, deep)
        local out = {}
        if ok and type(list) == "table" then
            for _, m in ipairs(list) do
                if type(m) == "table" and type(m.mapID) == "number" and type(m.name) == "string" and m.name ~= "" then
                    out[#out + 1] = { m.mapID, m.name }
                end
            end
        end
        table.sort(out, function(a, b) return a[2] < b[2] end)
        return out
    end
    local seen = {}
    local WORLD = 947
    for _, c in ipairs(children(WORLD, T.Continent)) do
        local g = { id = c[1], name = c[2], zones = {} }
        for _, z in ipairs(children(c[1], T.Zone, true)) do
            if not seen[z[1]] then seen[z[1]] = true; g.zones[#g.zones + 1] = z; tree.all[#tree.all + 1] = z end
        end
        if #g.zones > 0 then tree.groups[#tree.groups + 1] = g end
    end
    for _, z in ipairs(children(WORLD, T.Zone)) do
        if not seen[z[1]] then seen[z[1]] = true; tree.loose[#tree.loose + 1] = z; tree.all[#tree.all + 1] = z end
    end
    Who.tree = tree
    return tree
end

function Who.RaceMenu(owner) ticks(owner, Who.Races(), Who.races) end
function Who.ClassMenu(owner) ticks(owner, Who.Classes(), Who.classes) end

-- The top of the zones: Check All, the loose zones, and the continents (each opens its zones).
function Who.ZoneMenu(owner)
    local tree = Who.ZoneTree()
    local rows = {}
    for _, g in ipairs(tree.groups) do
        rows[#rows + 1] = { key = "g" .. g.id, name = g.name,
            open = function()
                ticks(owner, g.zones, Who.zones, { title = g.name, back = function() Who.ZoneMenu(owner) end })
            end }
    end
    ticks(owner, tree.loose, Who.zones, { rows = rows, scope = tree.all })
end

-- The Search button, or Enter in the box: ask with what is set. A filter only changes
-- what will be asked, so several can be set at once, however fast, and only the click on
-- Search goes to the game (which allows one /who in a few seconds).
function Who.Go()
    local page = Who.page
    return Who.Send(page and page.search:GetText() or "")
end

-- A filter or the box changed: the buttons say whether a new search is due.
function Who.Changed()
    local page = Who.page
    if not (page and page:IsShown()) then return end
    Who.PaintBar(page)
end

function Who.SortMenu(owner)
    local values = { level = LEVEL or L["Level"], name = NAME or L["Name"], class = CLASS or L["Class"] }
    W().OpenMenu(owner, Who.SORTS, values, Who.sort or "level", Who.Sort, 120)
end

-- What the card shows for the picked person: who, what they play and where, and the two
-- ways to reach them.
function Who.Spec(p)
    local rows = {}
    local function add(label, value)
        if value ~= nil and value ~= "" then rows[#rows + 1] = { label = label, value = tostring(value) } end
    end
    add(LEVEL or L["Level"], p.level)
    add(L["Race"], p.race)
    add(L["Zone"], p.zone)
    add(L["Guild"], p.guild)
    local icon
    if p.token and DUI.ClassIcon then icon = { DUI.ClassIcon(p.token) } end
    local r, g, b = 1, 1, 1
    if p.token then r, g, b = Style.ClassTextColor(p.token) end
    -- Only the buttons that apply: Invite when the game would let you (alone, or leading or assisting).
    local buttons = { { text = WHISPER or L["Whisper"], primary = true, onClick = function() Data().Whisper(Who.picked) end } }
    if Data().CanInviteName(p.name) then
        buttons[#buttons + 1] = { text = INVITE or L["Invite"], onClick = function() Data().Invite(Who.picked) end }
    end
    return { icon = icon, initial = p.name, title = p.name, color = { r, g, b }, sub = p.class, rows = rows,
        buttons = buttons }
end

function Who.PaintDetail()
    local page = Who.page
    if not (page and page.detail) then return end
    local person
    for _, p in ipairs(Who.list or {}) do if p.name == Who.picked then person = p end end
    local changed = page.detail:Set(person and Who.Spec(person) or nil)
    if ns.Window.PadChanged then ns.Window.PadChanged() end   -- the controller's X follows the card's button
    return changed
end

-- Page width (the target width while the window is resizing).
function Who.Width(page)
    return page.stack:Width() + 2 * Win.Parts.EDGE
end

-- The search box over four drop-downs, each with its word over it (Search and Reset beside them,
-- or under them when the window is narrow), then the count. width is the
-- page's width when it is just changing (a window being dragged), else the one it is going to.
local function layoutBar(page, width)
    local W_ = W()
    local R = ns.Rows
    local room = Who.room or 0
    local x0 = Who.EDGE + R.PANEL_IN
    local total = (width or Who.Width(page)) - room - 2 * Who.EDGE - 2 * R.PANEL_IN
    page.panel:ClearAllPoints()
    page.panel:SetPoint("TOPLEFT", page, "TOPLEFT", Who.EDGE, -Who.PANEL_Y)
    page.panel:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Who.EDGE - room, -Who.PANEL_Y)
    -- The box takes the panel's width. Search (the one that asks) and Reset sit at the right of the
    -- drop-downs when each drop-down keeps Who.DROP_MIN, else under them, at the panel's bottom right.
    local gap = W_.CHIP_GAP
    local btns = page.go:GetWidth() + page.reset:GetWidth() + 2 * gap
    local beside = math.floor((total - btns - 3 * gap) / 4) >= Who.DROP_MIN
    Who.beside = beside
    local lift = beside and Who.LIFT or 0
    page.panel:SetHeight(Who.PANEL_H - lift)
    page.search:ClearAllPoints()
    page.search:SetPoint("TOPLEFT", page, "TOPLEFT", x0, -Who.SEARCH_Y)
    page.search:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Who.EDGE - R.PANEL_IN - room, -Who.SEARCH_Y)
    page.go:ClearAllPoints()
    page.go:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Who.EDGE - R.PANEL_IN - room, -(beside and Who.DROP_Y or Who.BUTTON_Y))
    page.reset:ClearAllPoints()
    page.reset:SetPoint("RIGHT", page.go, "LEFT", -gap, 0)
    local w = math.floor((total - (beside and (btns + gap) or 0) - 3 * gap) / 4)
    for i, key in ipairs({ "race", "class", "zone", "sortBy" }) do
        local x = x0 + (i - 1) * (w + gap)
        local b, label = page[key], page[key .. "Label"]
        b:SetWidth(w)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", page, "TOPLEFT", x, -Who.DROP_Y)
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", page, "TOPLEFT", x + 2, -Who.LABEL_Y)
    end
    page.found:ClearAllPoints()
    page.found:SetPoint("TOPLEFT", page, "TOPLEFT", Who.EDGE + 2, -(Who.FOUND_Y - lift))
    page.rule:ClearAllPoints()
    page.rule:SetPoint("TOPLEFT", page, "TOPLEFT", Who.EDGE, -(Who.FOUND_Y - lift + 22))
    page.rule:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Who.EDGE - room, -(Who.FOUND_Y - lift + 22))
    page.stack.scroll:SetPoint("TOPLEFT", page, "TOPLEFT", Win.Parts.EDGE, -(Who.TOP - lift))
end

-- The card open or closed: the bar keeps to the list's side, and the list's right edge
-- moves off the card.
function Who.Fit(page, p)
    local room = ns.Window.Span() * p
    Who.room = room
    layoutBar(page)
    page.stack.scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -page.stack.side - room, Card().REST)
end

-- Click on a person: pick them (and open the card), or close it when it is the picked one.
local function pick(name)
    Who.picked = (Who.picked ~= name) and name or nil
    for _, b in ipairs(Who.rows or {}) do ns.Rows.Pick(b, b.spec.person.name == Who.picked) end
    Who.PaintDetail()
end

-- "Level 25" with the number colored: the game's own template formatted with the plain
-- number (it wants a number, not colored text), then the number painted.
function Who.LevelWord(level)
    local colored = Win.Parts.Hex({ Style.Pop() }) .. level .. "|r"
    local t = _G.UNIT_LEVEL_TEMPLATE
    if type(t) == "string" then
        local ok, words = pcall(string.format, t, level)
        if ok and type(words) == "string" then return (words:gsub(tostring(level), colored, 1)) end
    end
    return (LEVEL or L["Level"]) .. " " .. colored
end

-- What each filter's drop-down says, and lit when something is ticked.
function Who.SayFilters(page)
    say(page.race, Who.Summary(Who.races, Who.Races()))
    say(page.class, Who.Summary(Who.classes, Who.Classes()))
    say(page.zone, Who.Summary(Who.zones, Who.ZoneTree().all))
    for _, f in ipairs(Who.FILTERS) do page[f[1]].SetActive(next(Who[f[2]]) ~= nil) end
end

-- Search is off while the game makes us wait between two searches (so none is refused)
-- and lit when what is set is not what was last asked; Reset when there is nothing set.
function Who.PaintBar(page)
    page.go.SetOff(Who.Cooling() or Who.searching == true)
    page.go.SetActive(Who.Signature(page.search:GetText()) ~= Who.asked)
    page.reset.SetOff(not Who.Filtered())
    Who.SayFilters(page)
end

function Who.Render(page)
    page = page or Who.page
    if not (page and page:IsShown()) then return end
    layoutBar(page)
    local list, total = Data().Who()
    -- Asking: the old answer goes and the list says so, as Find a group does.
    if Who.searching then list, total = {}, 0 end
    list = Who.Sorted(list)
    Who.list = list
    local s = page.stack
    s:Begin()
    Who.rows = {}
    local still = false
    for _, p in ipairs(list) do
        local guild = (type(p.guild) == "string" and p.guild ~= "") and ("  " .. Win.Parts.Hex(Style.INK.LABEL) .. "<" .. p.guild .. ">|r") or ""
        -- Level, race and class apart, with a dot between.
        local hex, dot = Win.Parts.Hex, Win.Parts.Hex(Style.INK.OFF) .. "  ·  |r"
        local bits = {}
        -- The word and the number, the number colored: never fed through the game's "Level %d"
        -- template, which wants a plain number.
        if type(p.level) == "number" and p.level > 0 then bits[#bits + 1] = Who.LevelWord(p.level) end
        if (p.race or "") ~= "" then bits[#bits + 1] = p.race end
        if (p.class or "") ~= "" then bits[#bits + 1] = ns.Rows.Named(p.class, p.token) end
        local sub = table.concat(bits, dot)
        local b = ns.Rows.Row(s, { kind = "person", height = ns.Rows.PERSON, person = p, sep = true, icon = ns.Rows.ClassIcon(p.token),
            text = ns.Rows.Named(p.name, p.token) .. guild, sub = sub,
            value = p.zone or "", valueColor = Style.INK.TEXT, picked = p.name == Who.picked,
            onClick = function() pick(p.name) end,
            onMenu = function(row) ns.Rows.Menu(row, p.name, Data().CanInviteName(p.name)) end })
        Who.rows[#Who.rows + 1] = b
        if p.name == Who.picked then still = true end
    end
    if not still then Who.picked = nil end
    page.pieces = s:End()
    if Who.fresh then Win.Feel.Stagger(page.pieces, 0) end
    Who.fresh = nil
    -- "N found". The server sends 50 at most, so say when there were more.
    local count = #list
    if Who.searching then
        page.found:SetText("")
    elseif total > count then
        page.found:SetText(string.format(L["%s found, showing %d: narrow the search"], Win.Parts.Hex({ Style.Pop() }) .. total .. "|r", count))
    else
        page.found:SetText(string.format(L["%s found"], Win.Parts.Hex({ Style.Pop() }) .. count .. "|r"))
    end
    local note
    if Who.searching then note = L["Searching..."]
    elseif Who.waitMsg then note = Who.waitMsg
    elseif Who.failed then note = L["Nothing came back. Press Enter to search again."]
    elseif count == 0 then
        -- With what was asked under it, so a filter the game did not understand shows.
        note = Who.asked and (L["No one matches."] .. ((Who.askedText or "") ~= "" and (string.char(10) .. Who.askedText) or "")) or L["Search for a name, zone, class, guild or level."]
    end
    page.note:SetText(note or "")
    page.note:SetShown(note ~= nil)
    Who.Seek(page, Who.searching == true)
    -- What each drop-down shows now.
    local sortWord = { level = LEVEL or L["Level"], name = NAME or L["Name"], class = CLASS or L["Class"] }
    say(page.sortBy, sortWord[Who.sort or "level"])
    Who.PaintBar(page)
    Who.PaintDetail()
end

-- The bar fills over and over while the answer is awaited.
function Who.Seek(page, on)
    local bar = page.seek
    bar:SetShown(on)
    if not on then return end
    local M = DUI.Motion
    if not (M and M.On()) then bar:SetValue(1); return end
    local function loop()
        if not (Who.searching and bar:IsVisible()) then return end
        M.Tween(bar, 0, 1, Who.SEEK, function(v) bar:SetValue(v) end, loop)
    end
    loop()
end

function Who.Build(page)
    Who.page = page
    page.panel = ns.Rows.Panel(page)
    page.search = W().Input(page, { search = true, hint = L["Name, zone, class, guild or level"], maxLetters = 64,
        onChange = function() Who.Changed() end })
    page.search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        Who.Go()
    end)
    local function dropdown(key, word, onClick)
        local b = W().MenuButton(page, "", W().CHIP_HEIGHT)
        b.text:SetPoint("RIGHT", b.chevron, "LEFT", -6, 0)
        b.text:SetWordWrap(false)
        b:SetScript("OnClick", onClick)
        page[key] = b
        local fs = Style.Text(page, Style.SIZE.small, "LEFT")
        fs:SetText(word)
        Style.InkText(fs, "LABEL")
        page[key .. "Label"] = fs
    end
    dropdown("race", _G.RACE or L["Race"], function(self) Who.RaceMenu(self) end)
    dropdown("class", _G.CLASS or L["Class"], function(self) Who.ClassMenu(self) end)
    dropdown("zone", _G.ZONE or L["Zone"], function(self) Who.ZoneMenu(self) end)
    dropdown("sortBy", _G.WHO_SORT_LABEL or L["Sort by"], function(self) Who.SortMenu(self) end)
    page.go = W().Button(page, _G.SEARCH or L["Search"], W().CHIP_HEIGHT)
    page.go.FitWidth(0)
    page.go:SetScript("OnClick", function() Who.Go() end)
    page.reset = W().Button(page, _G.RESET or L["Reset"], W().CHIP_HEIGHT)
    page.reset.FitWidth(0)
    page.reset:SetScript("OnClick", function() Who.Reset() end)
    page.found = Style.Text(page, Style.SIZE.body, "LEFT")
    Style.InkText(page.found, "LABEL")
    page.seek = W().Bar(page, W().BAR_H)
    page.seek:SetWidth(Who.SEEK_W)
    page.seek:SetPoint("TOP", page, "CENTER", 0, -24)
    page.seek:SetMinMaxValues(0, 1)
    W().BarAccent(page.seek)
    page.seek:Hide()
    page.rule = page:CreateTexture(nil, "ARTWORK")
    page.rule:SetTexture(Win.Parts.WHITE)
    page.rule:SetVertexColor(1, 1, 1, 0.07)
    page.rule:SetHeight(1)
    page.stack = Win.Parts.Stack(page, { top = Who.TOP, bottom = Card().REST })
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", page, "CENTER", 0, 0)
    Style.InkText(page.note, "LABEL")
    page.note:Hide()
    -- Dragging the window's edge: the drop-downs have fixed widths, so they follow the page as it goes
    -- (the box and the buttons are anchored to its edges and already do).
    page:HookScript("OnSizeChanged", function(self, width)
        if type(width) == "number" and width > 0 and Who.page == self then layoutBar(self, width) end
    end)
    page.detail = Card().New(page, { refill = function() Who.Render() end,
        side = function(open) ns.Window.SetSide("who", open) end, fit = function(p) Who.Fit(page, p) end })
    page:HookScript("OnShow", function()
        local F = friends()
        if F and F.SetWhoToUi then pcall(F.SetWhoToUi, true) end
    end)
    page:HookScript("OnHide", function()
        local F = friends()
        if F and F.SetWhoToUi then pcall(F.SetWhoToUi, false) end
    end)
    DUI.RegisterEvent("UI_ERROR_MESSAGE", function(_, _, message) Who.Refused(message) end)
    DUI.RegisterEvent("WHO_LIST_UPDATE", function()
        Who.searching = false
        -- Closed but the page still counts as shown: only draw while visible (opening fills it).
        -- Fresh results: rows lift in one after another.
        if page:IsVisible() then Who.fresh = true; Who.Render(page) end
    end)
    -- Joining a group or losing the lead changes whether Invite can work, so the open
    -- card shows its buttons again.
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" }) do
        DUI.RegisterEvent(event, function()
            if page:IsVisible() then Who.PaintDetail() end
        end)
    end
end

function Who.Fill(page)
    Who.Render(page)
end

function Who.Pieces(page)
    local out = { page.panel, page.search, page.go, page.reset, page.race, page.class, page.zone, page.sortBy, page.found }
    for i, p in ipairs(page.pieces or {}) do
        if i > 10 then break end
        out[#out + 1] = p
    end
    return out
end
