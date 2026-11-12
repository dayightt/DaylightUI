-- The Daylight chat box (chat style "Daylight", the default): Daylight UI's own
-- message list and tabs in the corner panel, replacing the game's chat windows.
-- Chat style "Classic" is the game's windows restyled (Chat.lua alone). Switching
-- takes effect at once, no reload.
--
-- * Lines: every chat window's AddMessage is post-hooked with hooksecurefunc
--   (never the combat log) and only read. Lines arrive fully formatted by the
--   game (links, colors, class colors, timestamps, other addons' filters) along
--   with chat type id, event and arguments, per the game's AddMessage(text, r, g,
--   b, id, accessID, typeID, event, eventArgs) in ChatFrameOverrides.lua.
--   Nothing is ever written back on the window: an earlier hook that rewrote the
--   game's history entries caused errors.
--   A line that reaches several windows is kept once (by the event's line id, or
--   the same plain text within DEDUPE seconds; a secret line without an id only
--   from the main window). Short tags go on our copy (Tags.Shorten).
-- * Tabs: our own (W.Tab) along the top of the panel, each showing its kinds of
--   message (Kinds.lua). A tab with something new pulses (Feel).
-- * The game's windows, tabs and dock stay put at alpha 0 with mouse off. Never
--   hidden, moved or reparented: they still send, receive and feed whisper
--   replies. Typing uses the game's own edit box in our spot (Chat.Hold), as
--   in Classic.
-- * Links: clicks go to the game (SetItemRef, as its chat windows do). Hover
--   shows the tooltip above the panel (LinkTips).
-- * Floating, fading, the resize grip, history and Copy come from Chat.lua, with
--   our message list in place of the game's window.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style

local Box = {}
ns.Box = Box

Box.MAX = 500 -- lines kept, all tabs together
Box.TRIM = 100 -- lines over MAX before the oldest are dropped in one go
Box.DEDUPE = 0.25 -- seconds within which the same plain line from another window is a duplicate
Box.ANSWER = 5 -- seconds a system line after a query counts as its answer
Box.FORGET = 10 -- seconds a line's id or text is remembered for that
Box.TAB_PAD = 12 -- padding around a tab's label
Box.LIFT = 30 -- px the lines rise while typing, the edit box under them
Box.FOOT = 30 -- footer height, where the game's edit box sits
Box.ACTION_GAP = 6 -- gap between header icons
Box.STRIP_TOP = 8 -- how far the strip's clip extends over the row (for tab counts)
Box.WHEEL = 60 -- how far one wheel click scrolls the tabs
Box.EDGE = 24 -- dragging a tab this close to the strip's end scrolls the tabs
Box.EDGE_SPEED = 240 -- scroll speed, per second
Box.SIDE_SEEN = 6 -- seconds a just-opened second panel stays visible, floating or not

local cfg
-- A pane is one panel's message list and tab row. main is the corner panel, side
-- the second panel (tabs with side = true, see "The second panel" below). Buttons
-- are indexed by the tab's position in the single tabs list, so the tab editors
-- (Tabs.lua, Filter.lua) don't need to know which panel a tab is on.
local main = { buttons = {}, picked = 1, scroll = 0, scrollKey = "chatTabScroll" }
local side = { buttons = {}, scroll = 0, scrollKey = "chatSideTabScroll" }
local panes = { main, side }
Box.main, Box.side = main, side
local foot -- footer where you type (main panel)
local log = {}         -- every line kept, oldest first: { text, r, g, b, kind }
local labels = {} -- our tabs, for Feel's pulse (tab -> tab)
local hooked = setmetatable({}, { __mode = "k" })
local parked = setmetatable({}, { __mode = "k" }) -- game frame -> its original mouse setting

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

function Box.On() return cfg ~= nil and cfg.style ~= "classic" end
function Box.LineFadeIn() return cfg ~= nil and cfg.lineFadeIn ~= false end
function Box.Frame() return main.frame end
function Box.Panes() return panes end
function Box.IsList(cf) return cf ~= nil and (cf == main.frame or cf == side.frame) end
function Box.Labels() return labels end
function Box.Log() return log end

-- The tabs from the setting, or the defaults for a new chat.
local defaultTabs
function Box.Tabs()
    if cfg and type(cfg.tabs) == "table" and #cfg.tabs > 0 then
        for _, tab in ipairs(cfg.tabs) do ns.Kinds.Upgrade(tab) end
        return cfg.tabs
    end
    defaultTabs = defaultTabs or ns.Kinds.DefaultTabs()
    return defaultTabs
end

-- The pane a tab is on, and the first tab on a pane (nil if none).
local function paneOf(tab) return type(tab) == "table" and tab.side and side or main end
function Box.PaneOf(tab) return paneOf(tab) end

function Box.FirstOf(P)
    for i, tab in ipairs(Box.Tabs()) do
        if paneOf(tab) == P then return i end
    end
end

-- A pane's selected tab, falling back to its first if the selected one is gone.
local function pickedOf(P)
    local tabs, i = Box.Tabs(), P.picked
    if i and tabs[i] and paneOf(tabs[i]) == P then return i end
    return Box.FirstOf(P)
end

function Box.Picked() return pickedOf(main) or 1 end

-- Does the pane's selected tab show this event's lines?
function Box.Shows(P, event, ...)
    local i = pickedOf(P)
    if not i then return false end
    local _, k = ns.Kinds.Of(nil, event, { ... })
    return ns.Kinds.Shows(Box.Tabs()[i], k)
end

-- ---------------------------------------------------------------------
-- Incoming lines
-- ---------------------------------------------------------------------

local seenId, seenText = {}, {}
local seenFrom = setmetatable({}, { __mode = "v" }) -- text -> the window it first came from
local lastForget = 0

local function forget(now)
    if now - lastForget < Box.FORGET then return end
    lastForget = now
    for k, t in pairs(seenId) do if now - t > Box.FORGET then seenId[k] = nil end end
    for k, t in pairs(seenText) do
        if now - t > Box.FORGET then seenText[k], seenFrom[k] = nil, nil end
    end
end

-- First time this line is seen? Other windows may pass it along too.
local function fresh(cf, text, args)
    local now = GetTime()
    forget(now)
    -- A line id identifies one line, but many events (system, loot) carry 0; those
    -- are matched by text.
    local id = type(args) == "table" and args[11]
    if type(id) == "number" and not secret(id) and id > 0 then
        if seenId[id] then return false end
        seenId[id] = now
        return true
    end
    if secret(text) then return cf == _G.ChatFrame1 end
    -- The same text from another window shortly after is a copy. From the window that
    -- sent it first, it's a new line (said twice).
    local was, wasFrom = seenText[text], seenFrom[text]
    if was and now - was < Box.DEDUPE and wasFrom ~= cf then return false end
    seenText[text], seenFrom[text] = now, cf
    return true
end

-- Our copy of the line, with short tags when enabled and chat isn't locked down.
local function shape(text, event)
    if secret(text) or not ns.Tags.enabled or ns.Tags.Protected() then return text end
    if secret(event) or type(event) ~= "string" then event = nil end
    text = ns.Tags.Shorten(text, event) or text
    -- Drop the brackets around names: [Name] -> Name (the link still works).
    return (string.gsub(text, "(|H[Bb]?[Nn]?player:[^|]*|h)%[(.-)%](|h)", "%1%2%3"))
end

-- Does this tab show this line? By kind, or as an answer to a query made from it.
local function belongs(tab, e)
    return e[5] == "*" or e.here == tab or ns.Kinds.Shows(tab, e[5])
end

-- Sending a line or Shift-clicking a name (a /who) gets a system line back
-- ("[Bob]: Level 12...", "No player named..."). The tab you asked from may not
-- show system lines, so the answer shows there too.
local askedAt = -math.huge
function Box.Asked() askedAt = GetTime() end

-- The tab that asked, if this line answers it.
local function askedFrom(kind)
    if kind ~= "system" or GetTime() - askedAt >= Box.ANSWER then return nil end
    local tab = Box.Tabs()[Box.Picked()]
    if tab and not tab.combat then return tab end
end

-- Adds a line to our list, flagging alerts and our spam note in its extra data
-- (the redraw puts a glow behind alerts, Box.Glows).
local function show(P, e)
    if P.frame and Box.On() then P.frame:AddMessage(e[1], e[2], e[3], e[4], e.alert and "alert" or (e.note and "note") or nil) end
end

-- Adds a line to the log and to each panel's selected tab if it shows the kind.
-- Other tabs that show it (except "everything" tabs) pulse.
function Box.Push(e)
    log[#log + 1] = e
    -- Past MAX + TRIM, drop the oldest in one shift instead of one per line.
    local n = #log
    if n > Box.MAX + Box.TRIM then
        local drop = n - Box.MAX
        for i = 1, Box.MAX do log[i] = log[i + drop] end
        for i = n, Box.MAX + 1, -1 do log[i] = nil end
    end
    for i, tab in ipairs(Box.Tabs()) do
        if belongs(tab, e) then
            local P = paneOf(tab)
            if i == pickedOf(P) then show(P, e)
            elseif Box.On() and P.buttons[i] and e[5] ~= "*" and (not tab.all or e.alert) then Box.Alert(P.buttons[i], true) end
        end
    end
end

-- ---------------------------------------------------------------------
-- Spam: kept aside, with one quiet line at the bottom giving the count and a
-- "show" link that brings them in
-- ---------------------------------------------------------------------

Box.SPAM_KEEP = 100
Box.NOTE_GAP = 1 -- seconds; the note is redrawn at most this often (busy Trade)
local spamLog = {}
Box.spam = 0
local note -- the note's entry in the log
local lastNote, noteDue = -math.huge, false

local function dropNote()
    if not note then return end
    for i = #log, 1, -1 do
        if log[i] == note then table.remove(log, i); break end
    end
    note = nil
    -- The game passes each entry unpacked: message, r, g, b, then the extra values.
    -- The message can be secret, so only the tag is checked.
    for _, P in ipairs(panes) do
        if P.frame then P.frame:RemoveMessagesByPredicate(function(_, _, _, _, tag) return tag == "note" end) end
    end
end

local function noteText(n)
    local L = DUI.L
    local words = n == 1 and L["1 spam line hidden"] or string.format(L["%d spam lines hidden"], n)
    return DUI.Win.Parts.Hex(Style.INK.LABEL) .. words .. " · |r"
        .. DUI.Win.Parts.Hex({ Style.Accent() }) .. "|H" .. ns.Extras.LINK .. ":spam:all|h" .. L["show"] .. "|h|r"
end

-- The note stays the newest line: remove the old one, add the new one.
local function putNote()
    noteDue = false
    if Box.spam == 0 then return end
    lastNote = GetTime()
    dropNote()
    note = { noteText(Box.spam), nil, nil, nil, "*", note = true }
    Box.Push(note)
end

function Box.Spammed(e)
    spamLog[#spamLog + 1] = e
    if #spamLog > Box.SPAM_KEEP then table.remove(spamLog, 1) end
    Box.spam = Box.spam + 1
    -- A burst of ads is counted at once, but the note is redrawn at most once per
    -- NOTE_GAP, since each redraw removes the old note from the whole list.
    if noteDue then return end
    local wait = Box.NOTE_GAP - (GetTime() - lastNote)
    if wait <= 0 then putNote() return end
    noteDue = true
    C_Timer.After(wait, putNote)
end

function Box.ShowSpam()
    dropNote()
    local list = spamLog
    spamLog, Box.spam = {}, 0
    local dim = Style.INK.OFF
    for _, e in ipairs(list) do Box.Push({ e[1], dim[1], dim[2], dim[3], e[5] }) end
end

-- ---------------------------------------------------------------------
-- A glow behind each line that mentions you (alert words)
-- ---------------------------------------------------------------------

local glows = setmetatable({}, { __mode = "k" }) -- list -> its glows, plus how many are showing (n)

-- A line's current visibility (0 once the game has hidden it).
local function lineAlpha(line)
    if not line:IsShown() then return 0 end
    local a = line:GetAlpha()
    return (type(a) == "number" and not secret(a)) and a or 1
end

-- Sets a glow to its line's alpha a. The fade goes into the gradient colors,
-- because in game a gradient stayed at full under SetAlpha(0) after its line had
-- faded; at 0 it's hidden instead. Only repainted when a changes (again forces
-- it, for a redraw or an accent change).
Box.GLOW = 0.2
local function paintGlow(g, a, again)
    if g.a == a and not again then return end
    g.a = a
    if a <= 0 then g:Hide(); return end
    local ar, ag, ab = Style.Accent()
    g:SetGradient("HORIZONTAL", CreateColor(ar, ag, ab, Box.GLOW * a), CreateColor(ar, ag, ab, 0))
    g:Show()
end

function Box.Glows(f)
    local lines = f.visibleLines
    if type(lines) ~= "table" then return end
    local set = glows[f]
    if not set then set = { n = 0 }; glows[f] = set end
    local used = 0
    for _, line in ipairs(cfg and cfg.mentionGlow ~= false and lines or {}) do
        local info = line.messageInfo
        local x = type(info) == "table" and info.extraData
        if type(x) == "table" and x[1] == "alert" and line:IsShown() then
            used = used + 1
            local g = set[used]
            if not g then
                g = f:CreateTexture(nil, "BACKGROUND")
                g:SetTexture("Interface\\Buttons\\WHITE8X8")
                set[used] = g
            end
            g:ClearAllPoints()
            g:SetPoint("TOPLEFT", line, "TOPLEFT", -6, 1)
            g:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", -6, -1)
            g:SetPoint("RIGHT", f, "RIGHT")
            g.line = line
            paintGlow(g, lineAlpha(line), true)
        end
    end
    for i = used + 1, #set do set[i]:Hide(); set[i].line = nil; set[i].a = nil end
    set.n = used
end

-- The game fades lines itself with no redraw to tell us (UpdateFading), so each
-- glow copies its line's alpha every frame, but only while a glow is showing.
function Box.GlowStep()
    for _, set in pairs(glows) do
        for i = 1, set.n do
            paintGlow(set[i], lineAlpha(set[i].line))
        end
    end
end

-- Read-only hook on each window's AddMessage. Lines are kept in Classic too, so
-- switching to Daylight shows what came before.
function Box.Feed(cf, text, r, g, b, id, _, _, event, args)
    if type(text) == "nil" then return end
    if not secret(text) and (type(text) ~= "string" or text == "") then return end
    if not fresh(cf, text, args) then return end
    if type(event) == "nil" then event = ns.Kinds.Heard(cf) end
    local _, kind = ns.Kinds.Of(id, event, args)
    -- Whispers that a conversation keeps go to their own window, not the chat.
    -- Locked (secret) whispers and away, busy and offline notices still show here.
    if (kind == "whisper" or kind == "bnet") and ns.Talk.On() and cfg.whispersIn == "window"
        and ns.Talk.Keeps(event, args) then return end
    if secret(text) then
        Box.Push({ text, r, g, b, kind })
        return
    end
    -- Classic: kept as-is for a switch back. Spam, alerts and group links are
    -- Daylight box features.
    if not Box.On() then
        Box.Push({ shape(text, event), r, g, b, kind })
        return
    end
    -- Plain line: drop spam, light alert words, add role icons to group lines.
    local sender = type(args) == "table" and args[2]
    if secret(sender) or type(sender) ~= "string" or sender == "" then sender = nil end
    local guid = type(args) == "table" and args[12]    -- the event's arg12
    if secret(guid) or type(guid) ~= "string" then guid = nil end
    local body = type(args) == "table" and args[1] -- what they typed
    if secret(body) or type(body) ~= "string" then body = nil end
    if ns.Extras.IsSpam(kind, sender, text, guid, body) then
        Box.Spammed({ shape(text, event), r, g, b, kind })
        return
    end
    local line, hit = ns.Extras.Decorate(shape(text, event), kind, sender, guid)
    Box.Push({ line, r, g, b, kind, alert = hit or nil, here = askedFrom(kind) })
    if hit then ns.Feel.Shine() end
end

-- Called from the watcher only, never inside the game's code. Windows opened
-- later get hooked on the next pass.
function Box.Watch(cf)
    if hooked[cf] or type(cf) ~= "table" or type(cf.AddMessage) ~= "function" or ns.Tags.IsCombatLog(cf) then return end
    hooked[cf] = true
    -- Report our own errors instead of throwing them into the game's AddMessage.
    hooksecurefunc(cf, "AddMessage", function(...) DUI.SafeCall(Box.Feed, ...) end)
end

-- ---------------------------------------------------------------------
-- The game's chat, hidden
-- ---------------------------------------------------------------------

local function park(f)
    if type(f) ~= "table" or type(f.SetAlpha) ~= "function" then return end
    if f == _G.ChatFrame2 and ns.Tabs.combatShown then return end -- shown in a combat log tab
    if not parked[f] then
        parked[f] = { mouse = f.IsMouseEnabled and f:IsMouseEnabled(),
                      wheel = f.IsMouseWheelEnabled and f:IsMouseWheelEnabled(),
                      links = f.GetHyperlinksEnabled and f:GetHyperlinksEnabled() }
    end
    if f:GetAlpha() ~= 0 then f:SetAlpha(0) end
    if f.IsMouseEnabled and f:IsMouseEnabled() then f:EnableMouse(false) end
    if f.IsMouseWheelEnabled and f:IsMouseWheelEnabled() then f:EnableMouseWheel(false) end
    -- A window's links still catch clicks with its mouse off: under the box, its long
    -- [2. Trade - City] stole the click from our short line's name.
    if f.GetHyperlinksEnabled and f:GetHyperlinksEnabled() then f:SetHyperlinksEnabled(false) end
end

local function give(f, was)
    f:SetAlpha(1)
    if was.mouse and f.EnableMouse then f:EnableMouse(true) end
    if was.wheel and f.EnableMouseWheel then f:EnableMouseWheel(true) end
    if was.links and f.SetHyperlinksEnabled then f:SetHyperlinksEnabled(true) end
    parked[f] = nil
end

local function unpark()
    for f, was in pairs(parked) do give(f, was) end
end

function Box.Park(f) park(f) end
function Box.Unpark(f) if parked[f] then give(f, parked[f]) end end

-- The edit boxes are the windows' children and keep their own alpha (Chat.Input)
-- regardless of the window's.
local function ownAlpha(eb)
    if type(eb) == "table" and eb.SetIgnoreParentAlpha and not eb:IsIgnoringParentAlpha() then
        eb:SetIgnoreParentAlpha(true)
    end
end

-- ---------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------

local function dot(b, on)
    if not b.dot then return end
    if on and cfg and cfg.tabDots == false then on = false end
    b.unread = on and (b.unread or 0) + 1 or 0
    -- Only re-layout the row when the tab's width can change: the count appearing,
    -- disappearing or gaining a digit, not on every line in a busy chat.
    local relay = false
    if on then
        local words = b.unread > 99 and "99+" or tostring(b.unread)
        relay = #words ~= #(b.dotWords or "")
        b.dotWords = words
        b.dot:SetText(words)
        Style.InkText(b.dot, "pop")
    else
        b.dotWords = nil
    end
    local M = DUI.Motion
    if (b.dotOn == true) ~= (on == true) then
        b.dotOn = on or nil
        relay = true
        M.Tween(b.dot, b.dot:GetAlpha(), on and 1 or 0, M.FAST, function(a) b.dot:SetAlpha(a) end)
    end
    if on and M.On() then M.Pop(b.dot) end
    if relay then Box.LayoutTabs(b.pane) end
end

function Box.Alert(b, on)
    if not on then b.alert = nil; dot(b, false); b.Paint(b.hover == true); return end
    if b.picked then return end
    dot(b, true)
    local c = b.alertColor or {}
    b.alertColor = c
    c[1], c[2], c[3] = Style.Accent()
    b.alert = c
end

-- Tabs moved or removed (Tabs.lua): each count follows its tab, not its slot
-- (buttons are by slot). from[n] = tab n's previous slot.
function Box.KeepCounts(from)
    for _, P in ipairs(panes) do
        local was = {}
        for i, b in ipairs(P.buttons) do was[i] = b.unread or 0 end
        for n, b in ipairs(P.buttons) do
            local count = from[n] and was[from[n]] or 0
            if count ~= (b.unread or 0) then
                Box.Alert(b, false)
                if count > 0 and not b.picked then
                    b.unread = count - 1
                    Box.Alert(b, true)
                end
            end
        end
    end
end

-- Same remap for each panel's selected tab, so a panel whose tabs didn't change
-- stays put. Runs before the list is saved, since Refresh reads it.
function Box.Reindex(from)
    for _, P in ipairs(panes) do
        local now
        for n = 1, #from do
            if from[n] == P.picked then now = n end
        end
        P.picked = now
    end
end

-- ---------------------------------------------------------------------
-- More tabs than fit: they sit on a rail inside a clip strip ending at the header
-- icons. The wheel, dragging the row (its empty part, or right-dragging a tab)
-- and dragging a tab to the strip's end scroll it; a selected tab scrolls into
-- view. P.scroll is the current offset.
-- ---------------------------------------------------------------------

local pan

local function maxScroll(P)
    local width = P.strip and P.strip:GetWidth() or 0
    if width <= 1 then return 0 end
    return math.max(0, (P.railWidth or 0) - width)
end

local function setScroll(P, v)
    P.scroll = math.max(0, math.min(maxScroll(P), v))
    local rail, row = P.rail, P.row
    rail:ClearAllPoints()
    rail:SetPoint("TOPLEFT", row, "TOPLEFT", -P.scroll, 0)
    rail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", -P.scroll, 0)
end

function Box.ScrollTo(v, P)
    P = P or main
    if not P.rail then return end
    v = math.max(0, math.min(maxScroll(P), v))
    P.scrollGoal = v
    local M = DUI.Motion
    M.Tween(P.scrollKey, P.scroll, v, M.FAST, function(x) setScroll(P, x) end)
end

-- The strip only takes the wheel when there's something to scroll.
local function fitStrip(P)
    if not P.rail then return end
    P.strip:EnableMouseWheel(maxScroll(P) > 0)
    setScroll(P, P.scroll)
end

-- Scroll so tab i is fully in view.
function Box.Reveal(i)
    local P = paneOf(Box.Tabs()[i])
    local b = P.buttons[i]
    local width = P.strip and P.strip:GetWidth() or 0
    if not (b and b.x) or maxScroll(P) <= 0 then return end
    if b.x < P.scroll then Box.ScrollTo(b.x, P)
    elseif b.x + b:GetWidth() > P.scroll + width then Box.ScrollTo(b.x + b:GetWidth() - width, P) end
end

local function cursorAlong(P) return GetCursorPosition() / (P.row:GetEffectiveScale() or 1) end

function Box.PanMove()
    if pan then setScroll(pan.P, pan.from - (cursorAlong(pan.P) - pan.x)) end
end

function Box.PanStart(P)
    P = P or main
    if maxScroll(P) <= 0 then return false end
    DUI.Motion.Tween(P.scrollKey, P.scroll, P.scroll, 0)
    pan = { P = P, x = cursorAlong(P), from = P.scroll }
    P.row:SetScript("OnUpdate", Box.PanMove)
    return true
end

-- True when a scroll just finished.
function Box.PanStop()
    if not pan then return false end
    local P = pan.P
    pan = nil
    P.scrollGoal = P.scroll
    P.row:SetScript("OnUpdate", nil)
    return true
end

-- With the chat unlocked (header padlock), dragging the empty tab row moves the
-- panel when the tabs fit (otherwise it scrolls them), saved like an unlock
-- handle. Not in combat, so a slip can't move the chat.
function Box.MoveStart(P)
    if P.moving or (cfg and cfg.locked) or InCombatLockdown() then return end
    P.moving = true
    if P == main then ns.Chat.sizing = true else ns.Chat.sideSizing = true end
    ns.Feel.Sizing(true, P.panel)
    P.holder:StartMoving()
end

function Box.MoveStop(P)
    if not P.moving then return end
    P.moving = nil
    local key = P == main and "chat" or "chat.side"
    P.holder:StopMovingOrSizing()
    P.holder:SetUserPlaced(false) -- saved by us, not in the game's layout file
    DUI.Movers.Save(key)
    DUI.Movers.Apply(key)
    if P == main then ns.Chat.sizing = nil else ns.Chat.sideSizing = nil end
    ns.Feel.Sizing(false, P.panel)
end

local function buildStrip(P)
    local strip = CreateFrame("Frame", nil, P.row)
    P.strip = strip
    strip:SetClipsChildren(true)
    strip:SetPoint("TOPLEFT", P.row, "TOPLEFT", 0, Box.STRIP_TOP)
    strip:SetPoint("BOTTOMLEFT", P.row, "BOTTOMLEFT")
    strip:SetPoint("RIGHT", P.actions, "LEFT", -Box.ACTION_GAP, 0)
    strip:EnableMouse(true) -- right-click on empty space: Tabs.NewMenu
    strip:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ns.Tabs.NewMenu(self, P == side) end
    end)
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", function() if not Box.PanStart(P) then Box.MoveStart(P) end end)
    strip:SetScript("OnDragStop", function() if not Box.PanStop() then Box.MoveStop(P) end end)
    strip:SetScript("OnMouseWheel", function(_, delta)
        Box.ScrollTo((P.scrollGoal or P.scroll) - delta * Box.WHEEL, P)
    end)
    strip:SetScript("OnSizeChanged", function() fitStrip(P) end)
    P.rail = CreateFrame("Frame", nil, strip)
    setScroll(P, 0)
end

-- The combat log tab selected on a panel, if any; the game's own window shows there.
function Box.SyncCombat()
    local tabs, host = Box.Tabs(), nil
    if Box.On() then
        for _, P in ipairs(panes) do
            local i = pickedOf(P)
            if i and tabs[i].combat then host = P end
        end
    end
    ns.Tabs.ShowCombatLog(host ~= nil, host)
end

-- The current tab on its own panel: its lines, newest at the bottom.
function Box.Pick(i, animate)
    local tabs = Box.Tabs()
    if not tabs[i] then i = Box.FirstOf(main) or 1 end
    local P = paneOf(tabs[i])
    P.picked = i
    for n, b in ipairs(P.buttons) do
        local on = n == i
        if (b.picked == true) ~= on then
            b.Pick(on, animate)
            if on then ns.Feel.Glide(b, P.line) end
        end
        if on then Box.Alert(b, false) end
    end
    Box.Reveal(i)
    Box.SyncCombat()
    local frame = P.frame
    if not frame then return end
    local tab = tabs[i]
    -- A combat log tab shows the game's own window in our place.
    frame:SetShown(Box.On() and not tab.combat)
    if tab.combat then return end
    local function fill()
        frame:Clear()
        for _, e in ipairs(log) do
            if belongs(tab, e) then show(P, e) end
        end
        frame:ScrollToBottom()
    end
    -- Selected by the player: the old lines fade out, the tab's fade in.
    local M = DUI.Motion
    if not (animate and M.On()) then frame:SetAlpha(1); fill(); return end
    M.Tween(frame, frame:GetAlpha(), 0, M.FAST, function(a) frame:SetAlpha(a) end, function()
        if P.picked ~= i then return end
        fill()
        M.Tween(frame, 0, 1, M.NORMAL, function(a) frame:SetAlpha(a) end)
    end)
end

local function tabButton(P, i)
    local b = P.buttons[i]
    if b then return b end
    -- Its own underline stays hidden; one shared line glides between tabs.
    b = DUI.Widgets.Tab(P.rail, "", { size = ns.Chat.TabText(), paintLine = function(t) t:SetAlpha(0) end })
    b.pane = P
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button)
        -- The mouse was released after a drag, not a click (same frame).
        if Box.dropped == b and Box.droppedAt == GetTime() then return end
        if button == "RightButton" then
            ns.Tabs.OpenMenu(b, i)
        else
            Box.Pick(i, true)
            ns.Tabs.TalkHere(i)
        end
    end)
    -- Left drag moves the tab. Right drag scrolls the row, like dragging empty space.
    b:RegisterForDrag("LeftButton", "RightButton")
    b:SetScript("OnDragStart", function(_, button)
        if button == "RightButton" then Box.PanStart(P) else Box.DragStart(i) end
    end)
    b:SetScript("OnDragStop", function()
        if Box.PanStop() then Box.dropped, Box.droppedAt = b, GetTime() else Box.DragStop() end
    end)
    b:HookScript("OnEnter", function() b.hover = true end)
    b:HookScript("OnLeave", function() b.hover = nil end)
    -- Unread count, small, in the accent after the label.
    b.dot = Style.Text(b, Style.SIZE.tiny, "LEFT")
    b.dot:SetPoint("BOTTOMLEFT", b.text, "TOPRIGHT", 2, -6)
    b.dot:SetText("")
    b.dot:SetAlpha(0)
    b.unread = 0
    P.buttons[i] = b
    labels[b] = b
    return b
end

-- ---------------------------------------------------------------------
-- Dragging a tab along the row: it follows the mouse, the others glide aside
-- (FAST), and dropping saves the new order (Tabs.MoveTo), after which every tab
-- glides from where it was drawn. Dropped over the other panel, the tab moves
-- there (Tabs.SetSide). Slots are the pane's own tabs (drag.list holds their
-- indexes in the full list).
-- ---------------------------------------------------------------------

local drag

function Box.TabButton(i) return paneOf(Box.Tabs()[i]).buttons[i] end

local function placeTab(b, x)
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", b.pane.rail, "BOTTOMLEFT", x, 0)
    b:SetPoint("TOP", b.pane.rail, "TOP")
end

-- Mouse position along the row, in the row's units.
local function cursorX(P)
    local x = GetCursorPosition()
    return x / (P.row:GetEffectiveScale() or 1) - (P.row:GetLeft() or 0) + P.scroll
end

-- Eases a tab to x while another is dragged (b.seen = where it's drawn).
local function slideTab(b, x)
    b.slideKey = b.slideKey or {}
    local M = DUI.Motion
    M.Tween(b.slideKey, b.seen or b.x or 0, x, M.FAST, function(v) b.seen = v; placeTab(b, v) end)
end

function Box.DragStart(i)
    local tabs = Box.Tabs()
    local P = paneOf(tabs[i])
    local b = P.buttons[i]
    if not (P.row and b and b:IsShown()) then return end
    local list, slot = {}, 1
    for k, tab in ipairs(tabs) do
        if paneOf(tab) == P then
            list[#list + 1] = k
            if k == i then slot = #list end
        end
    end
    drag = { P = P, i = i, slot = slot, j = slot, list = list, off = cursorX(P) - (b.x or 0), level = b:GetFrameLevel() }
    for _, k in ipairs(list) do
        local o = P.buttons[k]
        DUI.Motion.Settle(o)
        o.seen = o.x or 0
    end
    b:SetFrameLevel(drag.level + 5)
    P.row:SetScript("OnUpdate", Box.DragMove)
end

function Box.DragMove(_, dt)
    if not drag then return end
    local P = drag.P
    -- Held at the strip's end, the tabs scroll under it.
    if dt and maxScroll(P) > 0 then
        local along = cursorX(P) - P.scroll
        if along < Box.EDGE then setScroll(P, P.scroll - Box.EDGE_SPEED * dt)
        elseif along > P.strip:GetWidth() - Box.EDGE then setScroll(P, P.scroll + Box.EDGE_SPEED * dt) end
    end
    local buttons, list = P.buttons, drag.list
    local b = buttons[drag.i]
    local width, total = b:GetWidth(), 0
    for _, k in ipairs(list) do total = total + buttons[k]:GetWidth() end
    local x = math.max(0, math.min(total - width, cursorX(P) - drag.off))
    b.seen = x
    placeTab(b, x)
    -- Its slot: count the tabs whose middle it has passed.
    local mid, j, at = x + width / 2, 1, 0
    for _, k in ipairs(list) do
        if k ~= drag.i then
            local w = buttons[k]:GetWidth()
            if at + w / 2 < mid then j = j + 1 end
            at = at + w
        end
    end
    if j == drag.j then return end
    drag.j = j
    -- The other tabs where they'd sit with it at j.
    local spot, slot = 0, 1
    for _, k in ipairs(list) do
        if k ~= drag.i then
            if slot == j then spot = spot + width end
            slideTab(buttons[k], spot)
            spot = spot + buttons[k]:GetWidth()
            slot = slot + 1
        end
    end
end

function Box.DragStop()
    if not drag then return end
    local d = drag
    drag = nil
    local P, buttons = d.P, d.P.buttons
    P.row:SetScript("OnUpdate", nil)
    local b = buttons[d.i]
    b:SetFrameLevel(d.level)
    Box.dropped, Box.droppedAt = b, GetTime()
    local seen = {}
    for _, k in ipairs(d.list) do
        local o = buttons[k]
        if o.slideKey then DUI.Motion.Tween(o.slideKey, 0, 0, 0) end
        seen[k] = o.seen or o.x or 0
        o.seen = nil
    end
    -- Dropped over the other panel: move the tab there.
    local other = P == main and side or main
    if Box.SideOn() and other.holder:IsMouseOver() and ns.Tabs.SetSide(d.i, other == side) then return end
    -- Each button glides from where its new tab was drawn.
    local to = d.list[d.j]
    local n = #Box.Tabs()
    local from = ns.Tabs.Order(n, d.i, to)
    for k = 1, n do
        local was = seen[from[k]]
        if was then buttons[k].x = was end
    end
    if to ~= d.i then ns.Tabs.MoveTo(d.i, to) end
    Box.LayoutTabs(P)
end

local function layoutTabs(P)
    if not P.row then return end
    local tabs, x, count = Box.Tabs(), 0, 0
    for i, tab in ipairs(tabs) do
        local b = tabButton(P, i)
        if paneOf(tab) == P then
            count = count + 1
            if b.words ~= tab.name then
                b.words = tab.name
                b.text:SetText(tab.name or "")
            end
            ns.Chat.SizeTab(b)
            b.FitWidth(Box.TAB_PAD + ((b.unread or 0) > 0 and (b.dot:GetStringWidth() or 0) + 2 or 0))
            -- A moved tab glides there; a new one slides in.
            local M, was, fresh = DUI.Motion, b.x, not b:IsShown()
            b.x = x
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", P.rail, "BOTTOMLEFT", x, 0)
            b:SetPoint("TOP", P.rail, "TOP")
            b:Show()
            labels[b] = b
            if fresh and was ~= nil then M.SlideIn(b, -8, 0, M.NORMAL)
            elseif was and was ~= x then M.Glide(b, was - x, 0, M.NORMAL) end
            x = x + b:GetWidth()
        else
            b:Hide(); b.x = 0; labels[b] = nil
        end
    end
    for i = #tabs + 1, #P.buttons do
        local b = P.buttons[i]
        b:Hide(); b.x = 0; labels[b] = nil
    end
    -- "+": new tab or combat log tab.
    if not P.plus then
        P.plus = DUI.Widgets.Tab(P.rail, "+", { size = Style.SIZE.head, paintLine = function(t) t:SetAlpha(0) end })
        P.plus:SetScript("OnClick", function(self) ns.Tabs.NewMenu(self, P == side) end)
        P.plus:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            DUI.Tips.Title(DUI.L["New tab"])
            DUI.Tips.Hint(DUI.L["Drag a tab to move it. Right-click: what it shows, rename, remove"])
            if maxScroll(P) > 0 then DUI.Tips.Hint(DUI.L["Mouse wheel or right-drag: slide the tabs"]) end
            DUI.Tips.Flush()
        end)
        P.plus:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    P.plus.FitWidth(Box.TAB_PAD)
    P.plus:ClearAllPoints()
    P.plus:SetPoint("BOTTOMLEFT", P.rail, "BOTTOMLEFT", x, 0)
    P.plus:SetPoint("TOP", P.rail, "TOP")
    P.railWidth = x + P.plus:GetWidth()
    P.rail:SetWidth(math.max(1, P.railWidth))
    fitStrip(P)
    -- Scroll a newly picked tab into view.
    local i = pickedOf(P)
    if i and count > (P.railTabs or 0) then Box.Reveal(i) end
    P.railTabs = count
end

function Box.LayoutTabs(P)
    if P then layoutTabs(P) return end
    for _, each in ipairs(panes) do layoutTabs(each) end
end

-- ---------------------------------------------------------------------
-- The message list
-- ---------------------------------------------------------------------

function Box.Font()
    if not cfg then return end
    for _, P in ipairs(panes) do
        local frame = P.frame
        if frame then
            local size = P == side and ns.Chat.SideTextSize() or ns.Chat.TextSize()
            frame:SetFont(Style.FontFile(ns.MEDIA.font), size, cfg.outline and "OUTLINE" or "")
            frame:SetShadowOffset(1, -1)
            frame:SetShadowColor(0, 0, 0, 0.9)
        end
    end
end

local function onWheel(f, delta)
    if IsControlKeyDown() then
        if delta > 0 then f:ScrollToTop() else f:ScrollToBottom() end
    elseif IsShiftKeyDown() then
        if delta > 0 then f:PageUp() else f:PageDown() end
    elseif delta > 0 then f:ScrollUp() else f:ScrollDown() end
end

-- The game's scroll keys move its selected window, which is parked out of sight.
-- Override bindings (never the player's saved binds) redirect whatever is bound
-- to them to buttons of ours, refreshed when bindings change. Only set out of
-- combat; ones set before a fight keep working during it.
Box.KEYS = { CHATPAGEUP = "PageUp", CHATPAGEDOWN = "PageDown", CHATBOTTOM = "ScrollToBottom" }

local keyButtons = {}
local function keyButton(command, method)
    local b = keyButtons[command]
    if b then return b end
    b = CreateFrame("Button", "DaylightUIChatKey" .. command, UIParent)
    b:SetScript("OnClick", function()
        local tab = Box.Tabs()[Box.Picked()]
        local f = tab and tab.combat and _G.ChatFrame2 or main.frame
        f[method](f)
    end)
    keyButtons[command] = b
    return b
end

function Box.BindKeys()
    if InCombatLockdown() then DUI.AfterCombat(Box.BindKeys, "chatBoxKeys") return end
    for command, method in pairs(Box.KEYS) do
        local b = keyButton(command, method)
        ClearOverrideBindings(b)
        if Box.On() then
            for _, key in ipairs({ GetBindingKey(command) }) do
                SetOverrideBindingClick(b, false, key, b:GetName(), "LeftButton")
            end
        end
    end
end

-- One panel's message list, tab row and header.
local function buildPane(P, holder, panel, name)
    local frame = CreateFrame("ScrollingMessageFrame", name, holder)
    P.frame = frame
    frame:SetFrameStrata("LOW") -- where the game's chat lines would sit
    frame:SetJustifyH("LEFT")
    frame:SetMaxLines(Box.MAX)
    frame:SetFadeDuration(3)
    frame:SetIndentedWordWrap(true)
    frame:SetTextCopyable(true) -- drag over lines to select, Ctrl+C copies
    frame:SetHyperlinksEnabled(true)
    frame:SetScript("OnHyperlinkClick", function(_, link, text, button)
        if ns.Extras.OnLink(link) or ns.Links.LinkQuestie(link, text, button)
            or ns.Links.ClubTicket(link, text, button) then return end
        if type(link) == "string" and not secret(link) and string.find(link, "^player")
            and IsModifiedClick and IsModifiedClick("CHATLINK") then Box.Asked() end
        SetItemRef(link, text, button, DEFAULT_CHAT_FRAME)
    end)
    frame:SetScript("OnHyperlinkEnter", function(f, link) ns.LinkTips.OnEnter(f, link) end)
    frame:SetScript("OnHyperlinkLeave", function(f) ns.LinkTips.OnLeave(f) end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", onWheel)
    frame:SetOnScrollChangedCallback(function(f) DUI.SafeCall(ns.Feel.Scrolled, f) end)
    ns.Feel.WatchLines(frame)
    frame:AddOnDisplayRefreshedCallback(function(f) DUI.SafeCall(Box.Glows, f) end)
    -- Tabs are parented to the panel, so they float away with it.
    P.row = CreateFrame("Frame", nil, panel)
    P.row:SetFrameStrata("LOW")
    Box.BuildActions(P)
    buildStrip(P)
end

local function build(holder)
    main.holder, main.panel = holder, ns.Chat.Panel()
    buildPane(main, holder, main.panel, "DaylightUIChatBox")
    DUI.RegisterEvent("UPDATE_BINDINGS", Box.BindKeys)
    Box.BuildFooter()
    Box.BuildSide()
end

-- ---------------------------------------------------------------------
-- Header icons: whispers (with unread count), copy, lock, options
-- ---------------------------------------------------------------------

function Box.BuildActions(P)
    local W, L = DUI.Widgets, DUI.L
    P.actions = CreateFrame("Frame", nil, P.row)
    P.actions:SetSize(1, ns.Chat.TAB_ROOM)
    -- The bubble belongs to the main panel, where the whisper tiles are.
    local list = {
        P == main and { "whispers", "ui-chat.png", L["Whispers"], function() ns.Hub.Toggle() end } or false,
        P == main and { "voice", "ui-voice.png", L["Voice chat and channels"], Box.ToggleVoice } or false,
        P == main and { "menu", "ui-micro-menu.png", ns.ChatMenu.Tip } or false, -- the game's button sits over it
        { "copy", "ui-copy.png", L["Copy chat"], function() ns.Copy.Show(P.frame) end },
        { "lock", "ui-unlock.png", function() return cfg and cfg.locked and L["Unlock the chat: drag the tab row to move it, a corner to size it"] or L["Lock the chat's spot and size"] end,
          function() DUI:Set("Chat", "locked", not (cfg and cfg.locked)) end },
        { "options", "ui-options.png", L["Chat options"], function() DUI.OptionsPanel.Show("Chat.chat") end },
    }
    P.icons, P.iconOrder = {}, {}
    for i = 1, #list do
        local a = list[i]
        if a then
            P.icons[a[1]] = W.IconButton(P.actions, a[2], a[3], a[4])
            P.iconOrder[#P.iconOrder + 1] = a[1]
        end
    end
    -- Unread whisper count, parented to the bubble so it moves with it.
    local bubble = P.icons.whispers
    if bubble then
        bubble.count = Style.Text(bubble, Style.SIZE.tiny, "LEFT")
        bubble.count:SetPoint("BOTTOMLEFT", bubble, "TOPRIGHT", -6, -10)
    end
end

-- Which icons the settings want. Copy and the bubble have their own switches, and
-- the bubble opens the whisper window, so "The chat only" has none.
local function iconWanted(name)
    if name == "copy" then return cfg.copyButton ~= false end
    if name == "whispers" then return cfg.whispersIn ~= "chat" and cfg.whispersButton ~= false end
    if name == "menu" then return cfg.menuButton ~= false end
    if name == "voice" then return cfg.voiceButton == true end
    return true
end

-- The headset opens the game's voice chat and channels window, same as its hidden
-- side button. It's a plain, unprotected game window. We call its Toggle without
-- the game's sound, since the icon plays our click.
function Box.ToggleVoice()
    local f = _G.ChannelFrame
    if type(f) == "table" and f.Toggle then f:Toggle() end
end

-- The icon the game's chat menu button sits over (ChatMenu.lua), when enabled.
function Box.MenuIcon()
    if not cfg or not Box.On() or not main.icons or not iconWanted("menu") then return nil end
    return main.icons.menu
end

-- Icons in a row from the right edge. A newly wanted one fades in, an unwanted
-- one fades out, the rest glide to close the gap. The tab strip ends at the row's
-- left so tabs get the room. The first layout is instant.
function Box.PlaceActions(P)
    P = P or main
    if not P.icons then return end
    local M, W = DUI.Motion, DUI.Widgets
    local x = 0
    for i = #P.iconOrder, 1, -1 do
        local b = P.icons[P.iconOrder[i]]
        local want, from, first = iconWanted(P.iconOrder[i]), b.at, b.placed == nil
        b.placed = true
        if want then
            b:ClearAllPoints()
            b:SetPoint("RIGHT", P.actions, "RIGHT", -x, 0)
            b.at = x
            if from and from ~= x then M.Glide(b, x - from, 0, M.FAST) end
            if not from and not first then
                b:Show()
                M.Tween(b, b:GetAlpha(), 1, M.FAST, function(a) b:SetAlpha(a) end)
            end
            x = x + W.ICON_BUTTON + Box.ACTION_GAP
        else
            b.at = nil
            if first then
                b:Hide()
            elseif from then
                M.Tween(b, b:GetAlpha(), 0, M.FAST, function(a) b:SetAlpha(a) end,
                    function() if not b.at then b:Hide() end end)
            end
        end
    end
    P.actions:SetWidth(x)
end

-- From Tiles.Refresh for the whisper count, from Apply for the lock icon.
function Box.PaintActions(unread)
    if not main.icons then return end
    local c = main.icons.whispers.count
    if unread then
        c:SetText(unread > 0 and tostring(unread) or "")
        Style.InkText(c, "pop")
        if unread > (Box.lastUnread or 0) and DUI.Motion.On() then DUI.Motion.Pop(c) end
        Box.lastUnread = unread
    end
    for _, P in ipairs(panes) do
        if P.icons then P.icons.lock.SetIcon(cfg and cfg.locked and "ui-lock.png" or "ui-unlock.png") end
    end
end

-- ---------------------------------------------------------------------
-- The footer, where you type
-- ---------------------------------------------------------------------

-- Whichever window's edit box the game opened (the combat log's while it's
-- selected in the dock).
local function typing() return ns.Chat.Typing() end

-- The footer is the field the game's own edit box sits in while typing; it sends,
-- keeps the channel and handles replies (Chat.Hold). Enter sends. There's no Send
-- button of ours: calling the game's Enter or OpenChat from addon code would send
-- the text tainted (a typed /cast or /target gets blocked) and write on its box.
function Box.BuildFooter()
    local L = DUI.L
    foot = CreateFrame("Frame", nil, ns.Chat.Panel())
    foot:SetFrameStrata("LOW")
    foot.field = CreateFrame("Button", nil, foot)
    foot.field:SetPoint("LEFT", foot, "LEFT", 0, 0)
    foot.field:SetPoint("RIGHT", foot, "RIGHT", 0, 0)
    foot.field:SetHeight(Box.FOOT)
    DUI.Widgets.InputLook(foot.field)
    -- Outline like a text box: half on hover, full while typing.
    function foot.field:HasFocus() return typing() end
    foot.field:SetScript("OnEnter", function(self) self.Ease() end)
    foot.field:SetScript("OnLeave", function(self) self.Ease() end)
    foot.hint = Style.Text(foot.field, Style.SIZE.body, "LEFT")
    foot.hint:SetPoint("LEFT", foot.field, "LEFT", 10, 0)
    foot.hint:SetText(L["Message..."])
    Style.InkText(foot.hint, "OFF")
    Box.PaintFooter()
end

-- Hide the hint while the game's edit box is open over the field (it shows its
-- own channel, "Guild:"). Called from the watcher.
function Box.PaintFooter()
    if not foot then return end
    local now = typing()
    foot.hint:SetShown(not now)
    if foot.typing ~= now then foot.typing = now; foot.field.Ease() end
end

-- ---------------------------------------------------------------------
-- The look: the full Daylight frame (mirroring the info panel) with the accent
-- line on top. Whisper tiles and the conversation join its right edge in the same
-- frame. Classic keeps its plain flat box.
-- ---------------------------------------------------------------------

function Box.Dress(on)
    -- The frames themselves, per the Border setting ("auto" follows the style).
    ns.Chat.DressPanels()
    for _, P in ipairs(panes) do
        local panel = P.panel
        if panel and (P == main or on) then
            local topLine = P.topLine
            if not topLine then
                topLine = panel:CreateTexture(nil, "OVERLAY")
                topLine:SetTexture("Interface\\Buttons\\WHITE8X8")
                topLine:SetHeight(2)
                P.topLine = topLine
            end
            topLine:ClearAllPoints()
            topLine:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -2)
            topLine:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -2)
            topLine:SetShown(on and cfg.topLine ~= false)
            if topLine:IsShown() then Style.PaintAccent(topLine, 0.9) end
        end
    end
    local grip = ns.Chat.grip
    if grip then
        grip:ClearAllPoints()
        grip:SetPoint("BOTTOMRIGHT", main.panel, "BOTTOMRIGHT", -2, 2)
    end
end

-- While typing, the lines rise and the box sits under them (eased).
local lift, liftGoal = 0, 0
function Box.Typing(on)
    -- Only when the box is at the panel's bottom, where it would cover lines.
    -- With the footer, it comes up under the lines only while typing.
    local room = Box.HasFooter() and (Box.FOOT + 6) or Box.LIFT
    local goal = (on and (Box.HasFooter() or cfg.typeLift ~= false) and ns.Chat.InputAt() == "bottom") and room or 0
    if goal == liftGoal or not main.frame then return end
    liftGoal = goal
    local M = DUI.Motion
    local fight = InCombatLockdown()
    M.Tween("chatBoxLift", lift, goal, fight and 0 or M.FAST, function(v)
        lift = v
        Box.Place()
    end)
end

function Box.Place()
    local frame = main.frame
    if not frame then return end
    local area = ns.Chat.Area()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", area, "TOPLEFT")
    frame:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, lift)
    if foot then
        -- Only visible while typing; fades and rises in with the lines.
        local k = math.min(1, lift / (Box.FOOT + 6))
        foot:ClearAllPoints()
        -- Top just under the lowest line, wherever the rise is.
        local y = math.max(-6, lift - Box.FOOT - 6)
        foot:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 0, y)
        foot:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, y)
        foot:SetHeight(Box.FOOT)
        foot:SetAlpha(k)
        foot:SetShown(Box.On() and Box.HasFooter() and k > 0)
    end
end

-- The footer (window kit), with the edit box at the bottom.
function Box.HasFooter() return cfg ~= nil and ns.Chat.InputAt() == "bottom" end
function Box.Field() return foot and foot.field end

-- A panel's tabs and header along its top.
local function layoutRow(P, panel, inset)
    P.row:ClearAllPoints()
    P.row:SetPoint("TOPLEFT", panel, "TOPLEFT", inset, -inset)
    P.row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -inset, -inset)
    P.row:SetHeight(ns.Chat.TAB_ROOM)
    Box.PlaceActions(P)
    Box.LayoutTabs(P)
    if P.actions then
        P.actions:ClearAllPoints()
        P.actions:SetPoint("RIGHT", P.row, "RIGHT", 0, 0)
    end
end

-- Fills the chat's spot in the panel, under the tabs.
function Box.Layout()
    if not main.frame then return end
    Box.Place()
    layoutRow(main, ns.Chat.Panel(), ns.Chat.inset or 0)
    Box.SideLayout()
end

-- ---------------------------------------------------------------------
-- The second panel: a separate chat box anywhere on screen for tabs marked side
-- (set from a tab's right-click menu, a drag onto the other panel, or the options
-- switch). It exists while at least one tab is on it.
-- It reads the same lines and settings as the corner panel and fades and floats
-- with it, unless sideHides says otherwise (its own fade area, "Chat.side"). It
-- has its own position, size and scale. Typing and whispers stay on the corner
-- panel. The game's combat log window moves here while a combat log tab is
-- selected here (Tabs.HoldLog).
-- side.body sits between the holder (whose alpha the fade engine owns) and the
-- rest, so the whole panel can fade in and out.
-- ---------------------------------------------------------------------

local sideOn = false
function Box.SideOn() return sideOn end

function Box.SideWanted()
    return Box.On() and Box.FirstOf(side) ~= nil
end

function Box.SideOver()
    return sideOn and side.holder:IsMouseOver()
end

function Box.BuildSide()
    local C = ns.Chat
    local holder = CreateFrame("Frame", "DaylightUIChatSide", UIParent)
    holder:SetFrameStrata("BACKGROUND")
    holder:SetSize(1, 1)
    holder:Hide()
    local body = CreateFrame("Frame", nil, holder)
    body:SetAllPoints(holder)
    local panel = CreateFrame("Frame", "DaylightUIChatSidePanel", body)
    Style.Shell(panel, {})
    local area = CreateFrame("Frame", nil, panel)
    local rule = panel:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    side.holder, side.body, side.panel, side.area, side.rule = holder, body, panel, area, rule
    buildPane(side, body, panel, "DaylightUIChatSideBox")
    DUI.Movers.Register(holder, "chat.side", "Second Chat Panel",
        function() return { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", -C.EDGE, DUI.Movers.Above(C.EDGE) } end,
        { scale = function(s) C.sideScale = s; holder:SetScale(s) end, active = Box.SideWanted, bottom = true })
    side.grip = C.MakeGrip({ holder = holder, parent = body, panel = panel, name = "DaylightUIChatSideGrip",
        edges = function() local both = 2 * (C.inset or 0); return both, both end,
        sizing = function(on) C.sideSizing = on or nil end,
        done = function(width, height)
            DUI.Movers.Save("chat.side")
            DUI:Set("Chat", "sideWidth", width)
            DUI:Set("Chat", "sideHeight", height)
        end })
    side.line = ns.Feel.NewLine(side.rail)
    side.pill = ns.Feel.NewPill(body, area, function() side.frame:ScrollToBottom() end)
    C.DressPanels()
end

function Box.SideLayout()
    if not (side.holder and cfg) then return end
    local C, panel, area = ns.Chat, side.panel, side.area
    local inset = C.inset or 0
    if not C.sideSizing then side.holder:SetSize(2 * inset + cfg.sideWidth, 2 * inset + cfg.sideHeight) end
    panel:SetShown(cfg.panelShown)
    panel:ClearAllPoints()
    panel:SetAllPoints(side.body)
    local s = Style.GetShell(panel)
    if s then
        s.opts.bgAlpha = C.SideBack()
        Style.LayoutShell(s)
    end
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", panel, "TOPLEFT", inset, -(inset + C.TAB_ROOM))
    area:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -inset, inset)
    side.rule:ClearAllPoints()
    side.rule:SetPoint("TOPLEFT", panel, "TOPLEFT", inset, -(inset + C.TAB_ROOM))
    side.rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -inset, -(inset + C.TAB_ROOM))
    side.frame:ClearAllPoints()
    side.frame:SetAllPoints(area)
    layoutRow(side, panel, inset)
end

-- Fades in when the first tab lands here and out with the last one. If the
-- selected tab is gone (another profile's tabs), pick again. While floating, a
-- panel that just appeared stays visible for SIDE_SEEN seconds: the mouse is in a
-- menu or the options, not over it, and with no lines yet you couldn't see where
-- it went. Not at login, it's already there.
local sideLoaded = false
function Box.SideApply()
    if not side.holder then return end
    local want = Box.SideWanted()
    if want then
        local i = pickedOf(side)
        if i ~= side.picked or not sideOn then Box.Pick(i) end
    end
    local loaded = sideLoaded
    sideLoaded = true
    if want == sideOn then return end
    sideOn = want
    if want then side.holder:Show() end
    -- At login it just shows; the UI's own login fade brings it in, and an animation
    -- started under the loading screen can get stuck transparent.
    if loaded then
        if want then ns.Chat.StayAwake(Box.SIDE_SEEN, true) end
        local M, body = DUI.Motion, side.body
        M.Tween(body, want and 0 or body:GetAlpha(), want and 1 or 0, M.NORMAL, function(a) body:SetAlpha(a) end,
            function() if not sideOn then side.holder:Hide() end end)
        -- The rise is a move only (Glide); the tween above owns body's alpha. Adding
        -- SlideIn's alpha animation left the panel invisible in game (a blip, then gone,
        -- with its tabs and links still clickable).
        if want then M.Glide(body, 0, -8, M.NORMAL) end
    end
    DUI.Movers.Recheck("chat.side")
    Box.SyncCombat()
end

-- ---------------------------------------------------------------------
-- On and off
-- ---------------------------------------------------------------------

-- From the watcher: hook each window once, and while on keep the game's chat
-- out of sight.
function Box.Pass()
    for _, cf in ipairs(ns.Chat.Frames()) do
        Box.Watch(cf)
        if Box.On() then
            local name = cf:GetName()
            park(cf)
            park(_G[name .. "Tab"])
            ownAlpha(_G[name .. "EditBox"] or cf.editBox)
        end
    end
    if Box.On() then
        park(_G.GeneralDockManager)
        Box.PaintFooter()
        ns.Tabs.HoldLog()
        if sideOn then ns.Feel.ListPill(side.pill, side.frame) end
    end
end

local wasOn
function Box.Apply(c)
    cfg = c
    if not main.frame then build(ns.Chat.Holder()) end
    local on = Box.On()
    local tab = Box.Tabs()[Box.Picked()]
    main.frame:SetShown(on and not (tab and tab.combat))
    main.row:SetShown(on)
    if not on then ns.Tabs.ShowCombatLog(false) end
    Box.Font()
    for _, P in ipairs(panes) do ns.Chat.LineTime(P.frame) end
    Box.Layout()
    -- Counts turned off: clear the visible ones now rather than on the tab's next line.
    if cfg.tabDots == false then
        for _, P in ipairs(panes) do
            for _, b in ipairs(P.buttons) do
                if (b.unread or 0) > 0 then dot(b, false) end
            end
        end
    end
    Box.PaintActions()
    ns.Talk.Apply(c)
    ns.Tiles.Apply(c)
    ns.Convo.Apply(c)
    ns.Hub.Apply(c)
    if not on and ns.Convo.Key() then ns.Convo.Close() end
    if not on then ns.Hub.Close(); ns.Filter.Close() end
    ns.Tiles.Refresh()
    -- Restyled on each change while on (the top line setting), and once when the
    -- style switches.
    if on or on ~= wasOn then Box.Dress(on) end
    if on ~= wasOn then
        wasOn = on
        Box.BindKeys()
        if on then
            ns.Tiles.Build()
            ns.Feel.UseRow(main.rail)
            Box.Pass()
            Box.Pick(Box.Picked())
            ns.Tabs.TalkHere(Box.Picked())
        else
            unpark()
            ns.Feel.UseRow(nil)
            DUI.Fade.Hold("Chat.chat", false) -- repaint the game's windows
        end
    end
    Box.SideApply()
end

-- Repainted after a style change (accent, text colors).
function Box.Repaint()
    for _, P in ipairs(panes) do
        for _, b in ipairs(P.buttons) do b.Paint(false); if b.picked then b.Pick(true) end end
        if P.topLine and P.topLine:IsShown() then Style.PaintAccent(P.topLine, 0.9) end
    end
    if side.rule then side.rule:SetColorTexture(1, 1, 1, 0.06) end
    Box.Font()
    ns.Tiles.Repaint()
    ns.Convo.Repaint()
    ns.Hub.Repaint()
    ns.Filter.Repaint()
end

-- ---------------------------------------------------------------------
-- History (History.lua): the newest plain lines with their kinds
-- ---------------------------------------------------------------------

function Box.Saved(max)
    local out = {}
    for i = #log, 1, -1 do
        if #out >= max then break end
        local e = log[i]
        -- Never save the spam note; restored after a reload it would be a dead line.
        if not e.note and type(e[1]) == "string" and not secret(e[1]) then table.insert(out, 1, { e[1], e[2], e[3], e[4], e[5] }) end
    end
    return out
end

-- /dui chat daylight | classic switches style at once (same as the options' Chat
-- style). With no argument, says which one is on.
function Box.Command(arg)
    local L = DUI.L
    local want = string.lower(arg or ""):match("%S+")
    if want == "daylight" or want == "classic" then
        DUI:Set("Chat", "style", want)
        DUI.Print(want == "daylight" and L["Chat style: Daylight."] or L["Chat style: Classic."])
        return
    end
    DUI.Print(Box.On() and L["Chat style: Daylight. /dui chat classic for the game's chat windows."]
        or L["Chat style: Classic. /dui chat daylight for the Daylight chat box."])
end

DUI.RegisterCommand("chat", Box.Command, DUI.L["/dui chat daylight|classic - the chat box style"])
