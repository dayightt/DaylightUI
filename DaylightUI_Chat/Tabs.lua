-- Daylight chat box tabs, edited from a tab's right-click menu: what it shows
-- (Filter.lua, kinds from Kinds.lua), rename (W.Prompt), new tab, combat log tab,
-- remove (with confirm). Tabs are stored in the tabs setting, written whole on
-- every change; the first change copies in the default tabs. Reordering is a
-- drag along the row (Box.DragStart).
-- A tab with side = true lives on the second panel (Box.lua), set by
-- Tabs.SetSide from its menu, a drag onto the other panel, or the options switch.
-- It's still one list, so everything here works by a tab's index in it.
--
-- A combat log tab ({ combat = true }) shows the game's combat log window
-- (ChatFrame2, with its filter bar) in the chat's place. The game docks it in the
-- main window's spot, so selecting the tab selects it in the dock and leaving
-- selects the main window again. On the second panel it's held in that panel's
-- place instead (Tabs.HoldLog).

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Tabs = {}
ns.Tabs = Tabs

-- Labels for each kind in the "Channels" window, in Kinds.ORDER.
Tabs.KIND_WORDS = {
    say = L["Say"], yell = L["Yell"], emote = L["Emotes"], whisper = L["Whispers"],
    bnet = L["Battle.net whispers"], party = L["Party"], instance = L["Instance"], raid = L["Raid"], warning = L["Raid warnings"],
    guild = L["Guild"], officer = L["Officer"], general = L["General channel"],
    trade = _G.TRADE or L["Trade"], [ns.Kinds.SERVICES] = L["Trade (Services)"], [ns.Kinds.TRADE_LOCAL] = L["Trade (Local)"],
    lfg = L["Looking for group"], defense = L["Local defense"],
    channel = L["Other channels"], loot = L["Loot"], money = L["Money"],
    progress = L["Experience and honor"], reputation = L["Reputation"], skill = L["Skill-ups"],
    achievement = L["Achievements"], npc = L["NPCs"], boss = L["Boss emotes"], system = L["System messages"],
    currency = L["Currency"], tradeskill = L["Tradeskills"], opening = L["Opening"], pet = L["Pet info"],
    misc = L["Falls and durability"], icons = L["Target icons"], bnalert = L["Friend alerts"], pvp = L["Battlegrounds"],
}

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and copy(v) or v end
    return out
end

-- A copy of the tabs to modify and then save.
local function editable() return copy(ns.Box.Tabs()) end
local function save(tabs) DUI:Set("Chat", "tabs", tabs) end

-- ---------------------------------------------------------------------
-- Changes (the tests call these too)
-- ---------------------------------------------------------------------

function Tabs.SetKind(i, kind, on)
    local tabs = editable()
    local tab = tabs[i]
    if not tab then return end
    if kind == "all" then
        tab.all = on or nil
    else
        -- From "Everything": every kind on except the one toggled.
        if tab.all then
            tab.kinds = {}
            for _, k in ipairs(ns.Kinds.ORDER) do tab.kinds[k] = true end
        end
        tab.all = nil
        tab.kinds = tab.kinds or {}
        -- A custom channel stays off even with "Other channels" on.
        if on then tab.kinds[kind] = true
        elseif ns.Kinds.Own(kind) then tab.kinds[kind] = false
        else tab.kinds[kind] = nil end
        tab.v = ns.Kinds.VERSION
    end
    save(tabs)
end

-- ---------------------------------------------------------------------
-- The channel you last talked in, per tab
-- ---------------------------------------------------------------------

-- Saved on the tab as talk: { type = "GUILD" } or { type = "CHANNEL", kind =
-- "trade" }. Channels are stored by kind since numbers differ per character.
-- Only what the game itself makes sticky (ChatTypeInfo), and never a whisper:
-- no names in the settings, and switching tabs shouldn't change who hears you.
Tabs.NO_TALK = { WHISPER = true, BN_WHISPER = true }

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function spoken(eb)
    local t = eb:GetAttribute("chatType")
    if type(t) ~= "string" or secret(t) or Tabs.NO_TALK[t] then return nil end
    local info = type(ChatTypeInfo) == "table" and ChatTypeInfo[t]
    if type(info) ~= "table" or info.sticky ~= 1 then return nil end
    if t ~= "CHANNEL" then return { type = t } end
    local target = eb:GetAttribute("channelTarget") -- may hold a name or a number
    if target == nil then return nil end -- the game only checks with one too
    local id = GetChannelName(target)
    if secret(id) then return nil end
    for _, c in ipairs(ns.Kinds.Joined()) do
        if c.id == id then return { type = t, kind = c.kind } end
    end
    return nil
end

-- A line about to be sent (from Recall.OnSend). The game has parsed any /g by now
-- and a command has cleared the box. Saved a moment later, outside the game's
-- send code.
function Tabs.Heard(eb)
    local Box = ns.Box
    if not Box.On() or type(eb) ~= "table" or eb ~= _G.ChatFrame1EditBox then return end
    local text = eb:GetText()
    if type(text) ~= "string" or secret(text) or text == "" or string.sub(text, 1, 1) == "/" then return end
    local i = Box.Picked()
    local tab = Box.Tabs()[i]
    local said = spoken(eb)
    if not said or type(tab) ~= "table" or tab.combat then return end
    local old = tab.talk
    if type(old) == "table" and old.type == said.type and old.kind == said.kind then return end
    C_Timer.After(0, function()
        local tabs = editable()
        if tabs[i] then
            tabs[i].talk = said
            save(tabs)
        end
    end)
end

-- Tab i selected: point the edit box at its channel by writing the box's
-- attributes, as the game's SetChatType does. Tested under a forced chat lockdown
-- and a line still went out, so this is allowed, and only done when something
-- changes. Never while typing: words already typed keep their recipient.
-- No UpdateHeader, the game runs it whenever it opens the box.
function Tabs.TalkHere(i)
    local tab = ns.Box.Tabs()[i]
    local talk = type(tab) == "table" and tab.talk
    local eb = _G.ChatFrame1EditBox
    if type(talk) ~= "table" or tab.side or tab.combat or type(eb) ~= "table" or ns.Chat.Typing() then return end
    local id
    if talk.type == "CHANNEL" then
        for _, c in ipairs(ns.Kinds.Joined()) do
            if c.kind == talk.kind then id = c.id end
        end
        if not id then return end -- you switched away
    end
    if eb:GetAttribute("chatType") == talk.type and eb:GetAttribute("stickyType") == talk.type
        and (not id or eb:GetAttribute("channelTarget") == id) then return end
    if id then eb:SetAttribute("channelTarget", id) end
    eb:SetAttribute("stickyType", talk.type)
    eb:SetAttribute("chatType", talk.type)
end

function Tabs.Rename(i, name)
    local tabs = editable()
    if not tabs[i] or type(name) ~= "string" or name == "" then return end
    tabs[i].name = name
    save(tabs)
end

function Tabs.Add(combat, onSide)
    local tabs = editable()
    if combat then
        tabs[#tabs + 1] = { name = _G.COMBAT_LOG or L["Combat Log"], combat = true, side = onSide or nil }
    else
        tabs[#tabs + 1] = { name = L["New tab"], kinds = {}, v = ns.Kinds.VERSION, side = onSide or nil }
    end
    save(tabs)
    return #tabs
end

-- One combat log window in the game, so one tab for it.
function Tabs.HasCombat()
    for _, tab in ipairs(ns.Box.Tabs()) do
        if tab.combat then return true end
    end
    return false
end

-- The corner panel always keeps a tab, since that's where you type.
local function lastMain(i)
    local tabs = ns.Box.Tabs()
    if not tabs[i] or tabs[i].side then return false end
    for k, tab in ipairs(tabs) do
        if k ~= i and not tab.side then return false end
    end
    return true
end

-- Where each tab comes from when tab i moves to j (new index -> old).
function Tabs.Order(n, i, j)
    local rest = {}
    for k = 1, n do if k ~= i then rest[#rest + 1] = k end end
    table.insert(rest, math.max(1, math.min(j, n)), i)
    return rest
end

-- Moves tab i to j (a drag along the row); the others close up.
function Tabs.MoveTo(i, j)
    local tabs = editable()
    if not (tabs[i] and tabs[j]) or i == j then return end
    local from = Tabs.Order(#tabs, i, j)
    local moved = {}
    for n = 1, #tabs do moved[n] = tabs[from[n]] end
    ns.Box.Reindex(from)
    ns.Filter.Reindex(from)
    save(moved)
    ns.Box.KeepCounts(from)
    ns.Box.Pick(j)
    ns.Filter.Changed()
end

function Tabs.Move(i, by) Tabs.MoveTo(i, i + by) end

function Tabs.Remove(i)
    local tabs = editable()
    if #tabs <= 1 or not tabs[i] or lastMain(i) then return end
    local B = ns.Box
    local pane = B.PaneOf(tabs[i])
    table.remove(tabs, i)
    local from = {}
    for n = 1, #tabs do from[n] = n < i and n or n + 1 end
    B.Reindex(from)
    ns.Filter.Reindex(from)
    save(tabs)
    B.KeepCounts(from)
    if B.FirstOf(pane) then B.Pick(B.FirstOf(pane)) else B.SyncCombat() end
    ns.Filter.Changed()
end

-- Moves tab i to the second panel (on) or back to the corner panel. False if it's
-- already there or it's the corner panel's last tab.
function Tabs.SetSide(i, on)
    local tabs = editable()
    local tab = tabs[i]
    on = on and true or nil
    if not tab or tab.side == on or lastMain(i) then return false end
    local B = ns.Box
    local left = B.PaneOf(tab)
    tab.side = on
    save(tabs)
    B.Pick(i, true)
    -- On the panel it left, switch to another tab if this one was showing.
    if left.picked == i then
        left.picked = nil
        if B.FirstOf(left) then B.Pick(B.FirstOf(left), true) end
    end
    B.SyncCombat()
    ns.Filter.Changed()
    return true
end

-- The options switch. On: the Loot tab moves over (or a new one if it was
-- removed). Off: every tab goes back to the corner panel.
function Tabs.SideShown() return ns.Box.FirstOf(ns.Box.side) ~= nil end

function Tabs.ShowSide(on)
    local B = ns.Box
    if on then
        if Tabs.SideShown() then return end
        for i, tab in ipairs(B.Tabs()) do
            if tab.kinds and tab.kinds.loot and not tab.all and Tabs.SetSide(i, true) then return end
        end
        local tabs = editable()
        local loot = ns.Kinds.DefaultTabs()[4]
        loot.side = true
        tabs[#tabs + 1] = loot
        save(tabs)
        B.Pick(#tabs)
    else
        local tabs = editable()
        for _, tab in ipairs(tabs) do tab.side = nil end
        B.side.picked = nil
        save(tabs)
        B.SyncCombat()
        ns.Filter.Changed()
    end
end

-- ---------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------

-- What tab i shows: the switches window (Filter.lua).
function Tabs.ShowMenu(owner, i)
    if not ns.Box.Tabs()[i] then return end
    ns.Filter.Open(i)
end

-- Text size, like the game's tab menu: its sizes as checkable entries plus the
-- outline, kept open while you try them. Uses the single textSize setting, so
-- the options page matches.
Tabs.SIZES = { 10, 12, 14, 16, 18, 20, 22, 24 }

function Tabs.SizeMenu(owner)
    local keys, values = {}, {}
    local words = _G.FONT_SIZE_TEMPLATE or L["%d pt"]
    for _, size in ipairs(Tabs.SIZES) do
        keys[#keys + 1] = size
        values[size] = string.format(words, size)
    end
    keys[#keys + 1] = "outline"
    values.outline = L["Outline"]
    DUI.Widgets.OpenMenu(owner, keys, values, nil, function(k)
        if k == "outline" then DUI:Set("Chat", "outline", not DUI:Get("Chat", "outline"))
        else DUI:Set("Chat", "textSize", k) end
    end, 140, { atCursor = true, keepOpen = true, rows = #keys,
        checked = function(k)
            if k == "outline" then return DUI:Get("Chat", "outline") == true end
            return ns.Chat.TextSize() == k
        end })
end

-- New tab picked: a plain one opens its Show window; a combat log has nothing to set.
function Tabs.New(owner, combat, onSide)
    local n = Tabs.Add(combat, onSide)
    ns.Box.Pick(n, true)
    if not combat then Tabs.ShowMenu(owner, n) end
end

-- The "+" and right-clicking empty space in the row (onSide: the second panel's).
function Tabs.NewMenu(owner, onSide)
    local keys = { "new" }
    local values = { new = L["New tab"], combat = L["New combat log tab"] }
    if not Tabs.HasCombat() then keys[2] = "combat" end
    DUI.Widgets.OpenMenu(owner, keys, values, nil, function(k)
        Tabs.New(owner, k == "combat", onSide)
    end, 180, { atCursor = true })
end

-- Right-click on tab i.
function Tabs.OpenMenu(owner, i)
    local tabs = ns.Box.Tabs()
    local tab = tabs[i]
    if not tab then return end
    local keys, values = {}, {}
    local function add(k, words) keys[#keys + 1] = k; values[k] = words end
    if not tab.combat then add("show", L["Channels"]) end
    add("rename", L["Rename"])
    add("size", string.format(L["Text size: %s"],
        string.format(_G.FONT_SIZE_TEMPLATE or L["%d pt"], ns.Chat.TextSize())))
    add("new", L["New tab"])
    if not Tabs.HasCombat() then add("combat", L["New combat log tab"]) end
    if tab.side then add("panel", L["Move to main panel"])
    elseif not lastMain(i) then add("panel", L["Move to second panel"]) end
    if #tabs > 1 and not lastMain(i) then add("remove", L["Remove tab"]) end
    DUI.Widgets.OpenMenu(owner, keys, values, nil, function(k)
        if k == "show" then Tabs.ShowMenu(owner, i)
        elseif k == "size" then Tabs.SizeMenu(owner)
        elseif k == "rename" then DUI.Widgets.Prompt(L["Tab name"], tab.name or "", function(name) Tabs.Rename(i, name) end)
        elseif k == "new" then Tabs.New(owner, false, tab.side)
        elseif k == "combat" then Tabs.New(owner, true, tab.side)
        elseif k == "panel" then Tabs.SetSide(i, not tab.side)
        elseif k == "remove" then Tabs.Remove(i) end
    end, 180, { atCursor = true, confirm = { remove = true }, more = { show = true, size = true } })
end

-- ---------------------------------------------------------------------
-- The combat log in the chat's place
-- ---------------------------------------------------------------------

local function select(cf)
    if type(FCFDock_SelectWindow) == "function" and GENERAL_CHAT_DOCK and type(cf) == "table" then
        FCFDock_SelectWindow(GENERAL_CHAT_DOCK, cf)
    end
end

-- On: show the game's combat log in our place; off: put it away. host is the pane
-- it shows on. Its filter bar hangs off the window's tab, parked out of sight, so
-- the bar keeps its own alpha.
Tabs.combatShown = false
Tabs.logSide = false
function Tabs.ShowCombatLog(on, host)
    local cl = _G.ChatFrame2
    if type(cl) ~= "table" then return end
    Tabs.logSide = on and host == ns.Box.side
    if on ~= Tabs.combatShown then
        Tabs.combatShown = on
        if on then
            select(cl)
            ns.Box.Unpark(cl)
            local bar = _G.CombatLogQuickButtonFrame_Custom
            if type(bar) == "table" and bar.SetIgnoreParentAlpha then bar:SetIgnoreParentAlpha(true) end
        else
            ns.Box.Park(cl)
            select(_G.ChatFrame1)
        end
    end
    Tabs.HoldLog()
end

-- Docked, the game keeps the combat log at the main window's spot. Selected on the
-- second panel, it's held in that panel's place instead (by the watcher, like
-- Chat.Hold does for the main window), and handed back afterwards with the room
-- the game leaves for its filter bar.
local logMoved = false

local function logTop(cl, rel)
    local bar = _G.CombatLogQuickButtonFrame_Custom
    local h = type(bar) == "table" and bar:GetHeight() or 0
    cl:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, -h)
end

function Tabs.HoldLog()
    local cl = _G.ChatFrame2
    if type(cl) ~= "table" then return end
    local area = Tabs.logSide and ns.Box.side.area
    if area then
        logMoved = true
        if cl.IsClampedToScreen and cl:IsClampedToScreen() then cl:SetClampedToScreen(false) end
        if cl:GetNumPoints() == 2 and select(2, cl:GetPoint(1)) == area then return end
        cl:ClearAllPoints()
        logTop(cl, area)
        cl:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT")
    elseif logMoved then
        logMoved = false
        cl:ClearAllPoints()
        logTop(cl, _G.ChatFrame1)
        cl:SetPoint("BOTTOMRIGHT", _G.ChatFrame1, "BOTTOMRIGHT")
    end
end
