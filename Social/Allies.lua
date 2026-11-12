-- Social window, Recent allies page: people the player grouped, traded or talked with,
-- from the client's own list (pinned first, then online, then most recent; old character
-- friends show up there as "legacy friends"). A search box and chips (All, Grouped,
-- Traded, Whispered), then Pinned and Recent. Each row has a status dot, the name in
-- class color, level and the shared activity below, and how long ago on the right.
-- Click selects for the footer's Invite, Whisper and Pin; right-click opens a menu.

local _, DUI = ...
DUI.Social = DUI.Social or {}
local ns = DUI.Social
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Allies = {}
ns.Allies = Allies

Allies.EDGE = 16
Allies.CHIPS_Y = 44
Allies.TOP = 76
Allies.ROW = 38
Allies.FILTERS = { "all", "party", "trade", "whisper" }
Allies.FILTER_WORD = { all = ALL or L["All"], party = L["Grouped"], trade = L["Traded"], whisper = L["Whispered"] }
Allies.filter = "all"
Allies.folds = {}

local function W() return DUI.Widgets end
local function Rows() return DUI.Lfg.Rows end
local function Data() return ns.Data end

function Allies.Tip(owner, a)
    if not (GameTooltip and a) then return end
    local T = DUI.Tips
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    T.Clear()
    local r, g, b = Style.ClassTextColor(a.class)
    T.Title(a.name, r, g, b)
    T.Sub(((a.level and string.format(L["Level %s"], a.level) .. " ") or "") .. Rows().ClassWord(a.class))
    T.Text(a.what .. (a.when and (" · " .. Data().Ago(a.when)) or ""))
    if a.location and a.online then T.Line(L["Zone"], a.location) end
    if a.note then T.Line(L["Note"], a.note) end
    if a.pinned then T.Text(L["Pinned: kept on your list"], Style.INK.LABEL) end
    T.Gap()
    T.Hint(L["Click: pick to whisper or invite"])
    T.Hint(L["Right-click: more"])
    T.Flush(GameTooltip)
    GameTooltip:Show()
end

function Allies.Menu(owner, a)
    local keys, values = {}, {}
    local function add(k, v) keys[#keys + 1] = k; values[k] = v end
    if a.online then
        add("whisper", WHISPER or L["Whisper"])
        add("invite", INVITE or L["Invite"])
    end
    add("pin", a.pinned and L["Unpin"] or L["Pin"])
    add("note", L["Set note..."])
    add("friend", L["Add friend"])
    add("ignore", IGNORE or L["Ignore"])
    W().OpenMenu(owner, keys, values, nil, function(k)
        if k == "whisper" then Data().Whisper(a.name)
        elseif k == "invite" then Data().Invite(a.name)
        elseif k == "pin" then Data().Pin(a, not a.pinned)
        elseif k == "note" then W().Prompt(string.format(L["A note for %s:"], a.short or a.name), a.note or "", function(text) Data().AllyNote(a, text) end)
        elseif k == "friend" then Data().AddFriend(a.name)
        elseif k == "ignore" then Data().Ignore(a.name) end
    end, nil, { atCursor = true })
end

local function picked()
    for _, a in ipairs(Allies.list or {}) do if a.guid == Allies.picked then return a end end
end

local function pick(guid)
    Allies.picked = guid
    for _, b in ipairs(Allies.rows or {}) do Rows().Pick(b, b.spec.ally.guid == guid) end
    Allies.PaintFooter()
end

function Allies.PaintFooter()
    local page = Allies.page
    if not page then return end
    local a = picked()
    local on = a ~= nil and a.online
    page.foot:Set({
        { text = INVITE or L["Invite"], primary = true, off = not on, onClick = function() local x = picked(); if x then Data().Invite(x.name) end end },
        { text = WHISPER or L["Whisper"], off = not on, onClick = function() local x = picked(); if x then Data().Whisper(x.name) end end },
        { text = a and a.pinned and L["Unpin"] or L["Pin"], off = a == nil, onClick = function() local x = picked(); if x then Data().Pin(x, not x.pinned) end end },
    })
end

function Allies.Filter(id)
    Allies.filter = id
    for k, b in pairs(Allies.page.chips) do b.SetOn(k == id) end
    Allies.Render()
end

local function keep(a, q)
    if Allies.filter ~= "all" and a.kind ~= Allies.filter then return false end
    if q == "" then return true end
    return string.lower(table.concat({ a.name, a.what or "", a.location or "", a.note or "" }, " ")):find(q, 1, true) ~= nil
end

local function row(s, a)
    local sub = ((a.level and string.format(L["Level %s"], a.level) .. " · ") or "") .. a.what
    local b = Rows().Row(s, { kind = "ally", height = Allies.ROW, ally = a,
        text = a.online and Rows().Named(a.name, a.class) or a.name, color = a.online and Style.INK.VALUE or Style.INK.OFF,
        sub = sub, subColor = a.online and Style.INK.LABEL or Style.INK.OFF, dot = ns.Window.StatusColor(a.status),
        value = Data().Short(a.when), valueColor = Style.INK.LABEL, picked = a.guid == Allies.picked,
        onClick = function() pick(Allies.picked ~= a.guid and a.guid or nil) end,
        onMenu = function(r) Allies.Menu(r, a) end,
        onEnter = function(r) Allies.Tip(r, a) end })
    Allies.rows[#Allies.rows + 1] = b
    if Allies.shine == a.guid then
        Win.Parts.Shine(b)
        Allies.shine = nil
    end
end

function Allies.Render(keepScroll)
    local page = Allies.page
    if not (page and page:IsShown()) then return end
    local s = page.stack
    local at = keepScroll and s:Scrolled()
    local q = string.lower(page.search:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local all = Data().Allies()
    Allies.list = all
    local pinned, recent = {}, {}
    for _, a in ipairs(all) do
        if keep(a, q) then
            if a.pinned or a.legacy then pinned[#pinned + 1] = a else recent[#recent + 1] = a end
        end
    end
    s:Begin()
    Allies.rows = {}
    local function count(list)
        local n = 0
        for _, a in ipairs(list) do if a.online then n = n + 1 end end
        return string.format(L["%d / %d"], n, #list)
    end
    if #pinned > 0 and not ns.Friends.Head(s, "pinned", L["Pinned"], count(pinned), Allies.folds, Allies.Render) then
        for _, a in ipairs(pinned) do row(s, a) end
    end
    if #recent > 0 and not ns.Friends.Head(s, "recent", L["Recent"], count(recent), Allies.folds, Allies.Render) then
        for _, a in ipairs(recent) do row(s, a) end
    end
    page.pieces = s:End()
    if at then s:ScrollTo(at) end
    if not picked() then Allies.picked = nil end
    local none = #pinned + #recent == 0
    page.note:SetShown(none)
    if not Data().AlliesReady() and #all == 0 then page.note:SetText(L["Asking who you played with..."])
    elseif #all == 0 then page.note:SetText(L["No allies yet. People you group, trade or talk with show here."])
    else page.note:SetText(L["No allies match."]) end
    Allies.PaintFooter()
end

-- Don't request data: C_RecentAllies.TryRequestRecentAlliesData is refused to addon
-- code even from a click. The list fills from RECENT_ALLIES_DATA_READY / _CACHE_UPDATE
-- when the client has it.

function Allies.Build(page)
    Allies.page = page
    page.search = W().Input(page, { search = true, hint = L["Search allies..."], maxLetters = 64,
        onChange = function() Allies.Render() end })
    page.search:SetPoint("TOPLEFT", page, "TOPLEFT", Allies.EDGE, -10)
    page.search:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Allies.EDGE, -10)
    page.chips = {}
    local x = Allies.EDGE
    for _, id in ipairs(Allies.FILTERS) do
        local b = W().Chip(page, Allies.FILTER_WORD[id])
        b.FitWidth()
        b:SetPoint("TOPLEFT", page, "TOPLEFT", x, -Allies.CHIPS_Y)
        b:SetScript("OnClick", function() Allies.Filter(id) end)
        b.SetOn(Allies.filter == id)
        page.chips[id] = b
        x = x + b:GetWidth() + W().CHIP_GAP
    end
    page.stack = Win.Parts.Stack(page, { top = Allies.TOP, bottom = 52 })
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", page, "CENTER", 0, 0)
    page.note:SetWidth(320)
    Style.InkText(page.note, "LABEL")
    page.note:Hide()
    page.foot = Win.Parts.Footer(page)
    DUI.RegisterEvent("RECENT_ALLIES_CACHE_UPDATE", function() ns.Window.Refresh("allies") end)
    DUI.RegisterEvent("RECENT_ALLIES_DATA_READY", function() ns.Window.Refresh("allies") end)
    DUI.RegisterEvent("RECENT_ALLY_DATA_UPDATED", function(_, guid)
        if type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) then Allies.shine = guid end
        ns.Window.Refresh("allies")
    end)
end

function Allies.Fill() Allies.Render() end

function Allies.Pieces(page)
    local out = { page.search }
    for _, id in ipairs(Allies.FILTERS) do out[#out + 1] = page.chips[id] end
    for i, p in ipairs(page.pieces or {}) do
        if i > 12 then break end
        out[#out + 1] = p
    end
    return out
end
