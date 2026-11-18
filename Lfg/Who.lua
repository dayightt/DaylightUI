-- Who page: a search box (the game's /who syntax: name, zone, class, guild, level or a
-- range like "20-25"), a Sort chip (name, class, level via C_FriendList.SortWho), how
-- many the server found, then the results: name in class color with guild, level, race
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
Who.PANEL_H = 96
Who.FOUND_Y = 118        -- "50 found"
Who.TOP = 146
Who.SORTS = { "level", "name", "class" }   -- the game's WHO_SORT_* keys
Who.WAIT = 6        -- s without an answer before the search counts as lost
Who.COOL = 3        -- s we wait between two /who, until the game says how long it wants
Who.MARGIN = 0.3    -- s added to what the game says
Who.SEEK, Who.SEEK_W = 0.8, 140

local function W() return DUI.Widgets end
local function Card() return DUI.Social.Detail end
local function Data() return ns.Data end

local function friends() return type(C_FriendList) == "table" and C_FriendList or nil end

-- The filters: race, class and zone narrow the /who itself (r-"Gnome" c-"Mage" z-"Elwynn
-- Forest"), so the server's 50 are all of that kind. The zones offered are the ones the
-- last answer had.
Who.race, Who.class, Who.zone = nil, nil, nil

function Who.Query(text)
    text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
    local parts = {}
    if text ~= "" then parts[#parts + 1] = text end
    if Who.race then parts[#parts + 1] = 'r-"' .. Who.race .. '"' end
    if Who.class then parts[#parts + 1] = 'c-"' .. ns.Rows.ClassWord(Who.class) .. '"' end
    if Who.zone then parts[#parts + 1] = 'z-"' .. Who.zone .. '"' end
    if #parts == 0 then return tostring(Data().Level()) end
    return table.concat(parts, " ")
end

-- A /who from the search box (Enter), a filter or a tab click. Empty search with no
-- filter = everyone at the player's level.
function Who.Send(text)
    local F = friends()
    if not (F and F.SendWho) then return end
    -- The game answers one /who in two seconds. The controls that ask are off for that
    -- long, so this is only a guard (Enter in the box).
    if Who.Cooling() then return false end
    text = Who.Query(text)
    Who.asked = text
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

-- The game turned the search down with "You must wait N s before using /who again" (a red
-- error line, in the player's language). Take its N and how long ago we asked as the
-- real wait, show the game's own sentence, and keep the controls off until it is up.
function Who.Refused(message)
    if not (Who.searching and Who.sentAt) or type(message) ~= "string" then return false end
    local n = tonumber(message:match("(%d+)"))
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
    Who.race, Who.class, Who.zone = nil, nil, nil
    local page = Who.page
    if page then page.search:SetText("") end
    Who.Changed()
end

function Who.Filtered()
    local page = Who.page
    return Who.race ~= nil or Who.class ~= nil or Who.zone ~= nil or (page ~= nil and (page.search:GetText() or "") ~= "")
end

function Who.Sort(mode)
    Who.sort = mode
    local F = friends()
    if F and F.SortWho then pcall(F.SortWho, mode) end
    Who.Render()
end

local function everyone() return _G.ALL or L["All"] end

-- A drop-down's menu: "everyone" first (the empty key), then the choices.
local function menu(owner, keys, values, current, onPick)
    local k, v = { "" }, { [""] = everyone() }
    for _, key in ipairs(keys) do k[#k + 1] = key; v[key] = values[key] end
    W().OpenMenu(owner, k, v, current or "", function(pick) onPick(pick ~= "" and pick or nil) end, 190,
        { rows = 10, pickFirst = true })
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

-- Races the game knows for this client, then any the last answer had that it didn't list.
function Who.Races()
    local seen, out = {}, {}
    local function add(name)
        if type(name) == "string" and name ~= "" and not seen[name] then seen[name] = true; out[#out + 1] = name end
    end
    local info = type(C_CreatureInfo) == "table" and C_CreatureInfo.GetRaceInfo
    if info then
        for id = 1, 90 do
            local ok, r = pcall(info, id)
            if ok and type(r) == "table" then add(r.raceName) end
        end
    end
    for _, p in ipairs(Who.list or {}) do add(p.race) end
    table.sort(out)
    return out
end

function Who.RaceMenu(owner)
    local races = Who.Races()
    local values = {}
    for _, r in ipairs(races) do values[r] = r end
    menu(owner, races, values, Who.race, function(r) Who.race = r; Who.Changed() end)
end

-- Class tokens: the game's list, then any the last answer had.
function Who.Classes()
    local tokens, seen = {}, {}
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    if type(names) == "table" then for token in pairs(names) do seen[token] = true; tokens[#tokens + 1] = token end end
    for _, p in ipairs(Who.list or {}) do
        if type(p.token) == "string" and not seen[p.token] then seen[p.token] = true; tokens[#tokens + 1] = p.token end
    end
    table.sort(tokens, function(a, b) return ns.Rows.ClassWord(a) < ns.Rows.ClassWord(b) end)
    return tokens
end

function Who.ClassMenu(owner)
    local tokens, values = Who.Classes(), {}
    for _, t in ipairs(tokens) do values[t] = ns.Rows.ClassWord(t) end
    menu(owner, tokens, values, Who.class, function(c) Who.class = c; Who.Changed() end)
end

function Who.Zones()
    local seen, out = {}, {}
    local function add(name)
        if type(name) == "string" and name ~= "" and not seen[name] then seen[name] = true; out[#out + 1] = name end
    end
    add(Who.zone)
    for _, p in ipairs(Who.list or {}) do add(p.zone) end
    table.sort(out)
    return out
end

function Who.ZoneMenu(owner)
    local zones = Who.Zones()
    local values = {}
    for _, z in ipairs(zones) do values[z] = z end
    menu(owner, zones, values, Who.zone, function(z) Who.zone = z; Who.Changed() end)
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

-- The search box over four drop-downs, each with its word over it, then the count.
local function layoutBar(page)
    local W_ = W()
    local R = ns.Rows
    local room = Who.room or 0
    local x0 = Who.EDGE + R.PANEL_IN
    local total = Who.Width(page) - room - 2 * Who.EDGE - 2 * R.PANEL_IN
    page.panel:ClearAllPoints()
    page.panel:SetPoint("TOPLEFT", page, "TOPLEFT", Who.EDGE, -Who.PANEL_Y)
    page.panel:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Who.EDGE - room, -Who.PANEL_Y)
    page.panel:SetHeight(Who.PANEL_H)
    page.search:ClearAllPoints()
    page.reset:ClearAllPoints()
    page.reset:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Who.EDGE - R.PANEL_IN - room, -(Who.SEARCH_Y + 1))
    page.go:ClearAllPoints()
    page.go:SetPoint("RIGHT", page.reset, "LEFT", -W_.CHIP_GAP, 0)
    page.search:SetPoint("TOPLEFT", page, "TOPLEFT", x0, -Who.SEARCH_Y)
    page.search:SetPoint("TOPRIGHT", page.go, "TOPLEFT", -W_.CHIP_GAP, 1)
    local gap = W_.CHIP_GAP
    local w = math.floor((total - 3 * gap) / 4)
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
    page.found:SetPoint("TOPLEFT", page, "TOPLEFT", Who.EDGE + 2, -Who.FOUND_Y)
    page.rule:ClearAllPoints()
    page.rule:SetPoint("TOPLEFT", page, "TOPLEFT", Who.EDGE, -(Who.FOUND_Y + 22))
    page.rule:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Who.EDGE - room, -(Who.FOUND_Y + 22))
    page.stack.scroll:SetPoint("TOPLEFT", page, "TOPLEFT", Win.Parts.EDGE, -Who.TOP)
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

-- Search is off while the game makes us wait between two searches (so none is refused)
-- and lit when what is set is not what was last asked; Reset when there is nothing set.
function Who.PaintBar(page)
    page.go.SetOff(Who.Cooling() or Who.searching == true)
    page.go.SetActive(Who.Query(page.search:GetText()) ~= Who.asked)
    page.reset.SetOff(not Who.Filtered())
    for _, key in ipairs({ "race", "class", "zone" }) do page[key].SetActive(Who[key] ~= nil) end
    page.race.text:SetText(Who.race or everyone())
    page.class.text:SetText(Who.class and ns.Rows.ClassWord(Who.class) or everyone())
    page.zone.text:SetText(Who.zone or everyone())
end

function Who.Render(page)
    page = page or Who.page
    if not (page and page:IsShown()) then return end
    layoutBar(page)
    local list, total = Data().Who()
    -- Asking: the old answer goes and the list says so, as Find a group does.
    if Who.searching then list, total = {}, 0 end
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
        note = Who.asked and (L["No one matches."] .. string.char(10) .. Who.asked) or L["Search for a name, zone, class, guild or level."]
    end
    page.note:SetText(note or "")
    page.note:SetShown(note ~= nil)
    Who.Seek(page, Who.searching == true)
    -- What each drop-down shows now.
    local sortWord = { level = LEVEL or L["Level"], name = NAME or L["Name"], class = CLASS or L["Class"] }
    page.race.text:SetText(Who.race or everyone())
    page.class.text:SetText(Who.class and ns.Rows.ClassWord(Who.class) or everyone())
    page.zone.text:SetText(Who.zone or everyone())
    page.sortBy.text:SetText(sortWord[Who.sort or "level"])
    for _, key in ipairs({ "race", "class", "zone" }) do page[key].SetActive(Who[key] ~= nil) end
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
