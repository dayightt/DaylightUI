local stub = require("stub")

-- Chat: the Daylight look over the game's chat windows (their art cleared, never
-- replaced), the side buttons hidden, and the extras done through the game's own
-- settings and message filters.

local filters, callbacks, active

-- What a window is signed up for, like the game's General tab. Every window takes
-- channel lines; which channels it keeps is its channel list.
local SHOWN = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_WHISPER", "CHAT_MSG_GUILD",
    "CHAT_MSG_PARTY", "CHAT_MSG_SYSTEM", "CHAT_MSG_CHANNEL", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY",
    "CHAT_MSG_CURRENCY", "CHAT_MSG_SKILL", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_COMBAT_FACTION_CHANGE" }

local function chatWindow(i, docked)
    local name = "ChatFrame" .. i
    local cf = CreateFrame("Frame", name, UIParent)
    cf:SetFont("GameFont", 14, "")
    cf.isDocked = docked
    cf:SetClampedToScreen(true)             -- as the game makes them
    cf:EnableMouse(true)                    -- its template's enableMouse (links, the wheel)
    cf:EnableMouseWheel(true)
    for _, s in ipairs(CHAT_FRAME_TEXTURES) do cf:CreateTexture(name .. s) end
    for _, s in ipairs(CHAT_FRAME_TEXTURES) do _G[name .. s]:SetTexture("art") end
    cf.buttonFrame = CreateFrame("Frame", name .. "ButtonFrame", cf)
    cf.ScrollBar = CreateFrame("Frame", nil, cf)
    cf.ScrollBar:Show()
    cf.ScrollToBottomButton = CreateFrame("Button", nil, cf)
    for _, e in ipairs(SHOWN) do cf:RegisterEvent(e) end
    cf.channelList, cf.zoneChannelList = {}, {}
    -- Its lines as the window keeps them, added and rewritten in place. Each is
    -- also the game's history entry (PackageEntry): `message` is [1], the values
    -- after r, g, b are in `extraData` (the event is 4th), and the arrival time
    -- is in `timestamp`.
    cf.lines = {}
    function cf:AddMessage(msg, r, g, b, infoID, accessID, typeID, event)
        table.insert(self.lines, { msg, event, r, g, b, timestamp = GetTime() })
    end
    function cf:GetNumMessages() return #self.lines end
    function cf:GetMessageInfo(i)
        local l = self.lines[i]
        if l then return l[1], l[3], l[4], l[5] end
    end
    function cf:GetID() return i end
    -- How long lines stay, as ScrollingMessageFrameMixin keeps it (120 s from
    -- ChatFrameMixin:OnLoad, fading on).
    cf.timeVisibleSecs, cf.shouldFadeAfterInactivity, cf.fadeResets = 120, true, 0
    function cf:SetTimeVisible(t) self.timeVisibleSecs = t end
    function cf:GetTimeVisible() return self.timeVisibleSecs end
    function cf:SetFading(on) self.shouldFadeAfterInactivity = not not on end
    function cf:GetFading() return self.shouldFadeAfterInactivity end
    function cf:ResetAllFadeTimes() self.fadeResets = self.fadeResets + 1 end
    -- The game's history. Entry 1 is the newest line, and it's the same table
    -- each time, as the game's buffer hands out its own entries.
    local ENTRY = {
        __index = function(l, k)
            if k == "message" then return rawget(l, 1) end
            if k == "extraData" then return { nil, nil, nil, rawget(l, 2), n = 4 } end
        end,
        __newindex = function(l, k, v)
            if k == "message" then rawset(l, 1, v) else rawset(l, k, v) end
        end,
    }
    cf.historyBuffer = { GetEntryAtIndex = function(_, n)
        local l = cf.lines[#cf.lines - n + 1]
        if not l then return nil end
        return setmetatable(l, ENTRY)
    end }
    -- The lines it shows (newest first) and its redraw, like the game's
    -- RefreshDisplay: each line gets its entry, its text and the game's alpha,
    -- then the callbacks run, all in the same frame.
    cf.visibleLines, cf.onDisplayRefreshedCallbacks = {}, {}
    function cf:AddOnDisplayRefreshedCallback(fn) table.insert(self.onDisplayRefreshedCallbacks, fn) end
    function cf:FakeRefresh()
        for n = 1, #self.lines do
            local line = self.visibleLines[n] or self:CreateFontString()
            self.visibleLines[n] = line
            local e = self.historyBuffer:GetEntryAtIndex(n)
            line.messageInfo = e
            line:SetText(e.message)
            line:SetAlpha(1)
        end
        for _, fn in ipairs(self.onDisplayRefreshedCallbacks) do fn(self) end
    end
    local tab = CreateFrame("Button", name .. "Tab", UIParent)
    for _, k in ipairs({ "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight" }) do
        tab[k] = tab:CreateTexture(); tab[k]:SetTexture("tab art")
    end
    tab.Text = tab:CreateFontString()
    tab.Text:SetFont("GameFont", 10, "")
    local eb = CreateFrame("EditBox", name .. "EditBox", UIParent)
    eb:SetFont("GameFont", 14, "")
    eb.header = eb:CreateFontString()
    eb.header:SetFont("GameFont", 14, "")
    for _, k in ipairs({ "Left", "Right", "Mid" }) do
        local t = eb:CreateTexture(name .. "EditBox" .. k); t:SetTexture("box art")
    end
    eb.focusLeft = eb:CreateTexture(); eb.focusLeft:SetTexture("focus art")
    table.insert(CHAT_FRAMES, name)
    return cf
end

-- style is "classic" (the game's windows, most tests here) unless asked for
-- "daylight" (the Daylight chat box, the module's default).
local function login(before, style)
    local DUI = stub.Load({ chat = true, before = function()
        _G.CHAT_FRAMES = {}
        _G.CHAT_FRAME_TEXTURES = { "Background", "TopLeftTexture", "ButtonFrameBackground" }
        _G.GeneralDockManager = CreateFrame("Frame", "GeneralDockManager", UIParent)
        _G.GENERAL_CHAT_DOCK = GeneralDockManager
        chatWindow(1, true)
        chatWindow(2, true)
        chatWindow(3, false)
        _G.FCFDock_GetSelectedWindow = function() return ChatFrame2 end
        CreateFrame("Button", "ChatFrameChannelButton", UIParent):Show()
        CreateFrame("Button", "QuickJoinToastButton", UIParent):Show()
        stub.cvars = {}
        _G.GetCVar = function(k) return stub.cvars[k] end
        _G.SetCVar = function(k, v) stub.cvars[k] = v end
        filters, callbacks = {}, {}
        active = { true, true, true }
        _G.FCF_IsChatWindowIndexActive = function(id) return active[id] == true end
        _G.COMBATLOG = nil
        _G.ChatFrameUtil = {
            AddMessageEventFilter = function(e, fn) filters[e] = fn end,
            RemoveMessageEventFilter = function(e) filters[e] = nil end,
        }
        _G.EventRegistry = { RegisterCallback = function(_, e, fn, owner) callbacks[e] = function(...) fn(owner, ...) end end }
        if before then before() end
    end })
    -- A new profile floats the chat (DB.StandardStart). These tests start from the
    -- module's own default and pick the other ways themselves.
    DUI:Set("Chat", "hides", "fightsIdle")
    DUI:Set("Chat", "style", style or "classic")
    stub.RunTimers()
    return DUI
end

T.test("chat: our panel behind the dock, the game's art cleared, our font at the game's size", function()
    login()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local panel = _G.DaylightUIChatPanel
    T.truthy(panel, "a panel behind the dock")
    T.truthy(DaylightUI.Style.GetShell(panel), "in our shell")
    T.eq(panel:GetParent(), _G.DaylightUIChat, "on the corner holder, which moves as one")
    T.eq(ChatFrame1Background.__texture, nil, "the game's background cleared")
    T.eq(ChatFrame1:GetFont(), DaylightUI.Style.FONT, "our font")
    T.eq(select(2, ChatFrame1:GetFont()), 14, "at the game's size")
end)

T.test("chat: flat tabs with a line under the selected one; our input box", function()
    login()
    T.eq(ChatFrame2Tab.ActiveMiddle.__texture, nil, "the tab's art cleared")
    T.eq(ChatFrame2Tab.Text:GetFont(), DaylightUI.Style.FONT)
    local chat = stub.chatModule.Chat
    stub.chatModule.Chat.Pass()
    T.eq(ChatFrame1EditBoxMid.__texture, nil, "the input box's art cleared")
    T.eq(ChatFrame1EditBox.focusLeft.__texture, nil)
    T.eq(ChatFrame1EditBox:GetFont(), DaylightUI.Style.FONT, "our font in it")
    T.truthy(chat, "loaded")
end)

T.test("chat: a window out of the dock gets its own panel; docked ones share the dock's", function()
    login()
    local chat = stub.chatModule.Chat
    chat.Pass()
    local own
    for _, c in ipairs({ ChatFrame3:GetChildren() }) do
        if DaylightUI.Style.GetShell(c) then own = c end
    end
    T.truthy(own and own:IsShown(), "the undocked window's panel")
    -- The corner panel's thin border, not the heavy window frame, which is wider
    -- than the margin and sat over the window's bottom lines.
    local s = DaylightUI.Style.GetShell(own)
    T.truthy(s.opts.flat, "flat, like the corner panel")
    T.eq(s.opts.borderPx, 1, "its 1 px border")
    ChatFrame3.isDocked = true
    chat.Pass()
    T.falsy(own:IsShown(), "docked again: the dock's panel covers it")
end)

T.test("chat: the Scale slider sizes the panel and the docked windows with their tabs; an undocked one stays the game's", function()
    local DUI = login()
    local chat = stub.chatModule.Chat
    DUI:Set("general", "scale", 1.2)
    DUI.Movers.ApplyAll()
    stub.RunTimers()
    chat.Pass()
    T.near(DaylightUIChat:GetScale(), 1.2, 0.001, "our panel")
    T.near(ChatFrame1:GetScale(), 1.2, 0.001, "the main window (its text with it)")
    T.near(ChatFrame2:GetScale(), 1.2, 0.001, "a docked one")
    T.near(GeneralDockManager:GetScale(), 1.2, 0.001, "the tab row")
    T.near(ChatFrame3:GetScale(), 1, 0.001, "pulled out of the dock: the game's size (it saves its spot in its own units)")
    ChatFrame3.isDocked = true
    chat.Pass()
    T.near(ChatFrame3:GetScale(), 1.2, 0.001, "docked again: scaled with the rest")
    DUI:Set("general", "scale", 1)
    DUI.Movers.ApplyAll()
    stub.RunTimers()
    T.near(ChatFrame1:GetScale(), 1, 0.001, "back to normal at once")
end)

T.test("chat: the side buttons hidden, and kept hidden", function()
    login()
    T.falsy(ChatFrameChannelButton:IsShown())
    ChatFrameChannelButton:Show()
    T.falsy(ChatFrameChannelButton:IsShown(), "the game showing it again: hidden again")
    T.falsy(ChatFrame1.buttonFrame:IsShown())
end)

T.test("chat: class colors and timestamps are the game's own settings", function()
    login()
    T.eq(stub.cvars.chatClassColorOverride, "0", "class colors on")
    T.eq(stub.cvars.showTimestamps, nil, "timestamps left to the game by default")
    DaylightUI:Set("Chat", "timestamps", "%H:%M ")
    DaylightUI:Set("Chat", "classColors", false)
    stub.RunTimers()
    T.eq(stub.cvars.showTimestamps, "%H:%M ")
    T.eq(stub.cvars.chatClassColorOverride, "1")
    DaylightUI:Set("Chat", "timestamps", "%I:%M %p ")
    stub.RunTimers()
    T.eq(stub.cvars.showTimestamps, "%I:%M %p ", "a 12-hour clock with AM/PM")
end)

T.test("chat: the Timestamps list has the game's six formats, 12-hour ones too", function()
    local DUI = login()
    local page = DUI.Options.GetPage("Chat.chat")
    local found
    for _, g in ipairs(page.groups) do
        for _, it in ipairs(g.items) do
            if it.key == "timestamps" then found = it end
        end
    end
    T.truthy(found, "the Timestamps row")
    -- TIMESTAMP_FORMAT_HHMM ... _HHMMSS_24HR, the game's Social settings, in its order.
    T.deq(found.order, { "game", "none", "%I:%M ", "%I:%M:%S ", "%I:%M %p ", "%I:%M:%S %p ", "%H:%M ", "%H:%M:%S " })
    for _, key in ipairs(found.order) do T.truthy(found.values[key], "a label for " .. key) end
end)

-- Records every hook put on a chat window's AddMessage. The Daylight chat box's
-- read-only one (Box.lua) goes on once per window, never on the combat log.
local function countHooks()
    local hooks, orig = {}, _G.hooksecurefunc
    _G.hooksecurefunc = function(tbl, name, fn)
        if name == "AddMessage" then hooks[tbl] = (hooks[tbl] or 0) + 1 end
        return orig(tbl, name, fn)
    end
    return hooks, function() _G.hooksecurefunc = orig end
end

local GUILD, GUILD_SHORT = "|Hchannel:GUILD|h[Guild]|h Bob: hi", "|Hchannel:GUILD|h[G]|h Bob: hi"

T.test("chat: Classic short tags from the game's redraw; each window's AddMessage hooked once, read only", function()
    local hooks, restore
    login(function() hooks, restore = countHooks() end)
    local Chat = stub.chatModule.Chat
    Chat.Pass(); Chat.Pass()
    restore()
    T.eq(hooks[ChatFrame1], 1, "the main window hooked once")
    T.eq(hooks[ChatFrame3], 1, "every window")
    local cf = ChatFrame1
    cf:AddMessage(GUILD, 0, 1, 0, 1, 1, 1, "CHAT_MSG_GUILD")
    cf:FakeRefresh()
    T.eq(cf.lines[#cf.lines][1], GUILD_SHORT, "the history entry shortened")
    T.eq(cf.visibleLines[1]:GetText(), GUILD_SHORT, "and the line drawn short in the same frame")
    cf:AddMessage("|Hchannel:channel:2|h[2. Trade - City]|h WTS", 1, 1, 1, 1, 1, 1, "CHAT_MSG_CHANNEL")
    _G.CHAT_SAY_GET = "%s says: "
    cf:AddMessage("|Hplayer:Bob|h[Bob]|h says: hi", 1, 1, 1, 1, 1, 1, "CHAT_MSG_SAY")
    cf:FakeRefresh()
    _G.CHAT_SAY_GET = nil
    local n = #cf.lines
    T.eq(cf.lines[n - 1][1], "|Hchannel:channel:2|h[T]|h WTS", "trade")
    T.eq(cf.lines[n][1], "[S] |Hplayer:Bob|h[Bob]|h: hi", "say, by the line's own event")
    T.eq(cf.visibleLines[3]:GetText(), GUILD_SHORT, "an older line drawn again stays short")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: short tags: each line looked at once, never the combat log", function()
    login(function() _G.COMBATLOG = ChatFrame2 end)
    stub.chatModule.Chat.Pass()
    ChatFrame2:AddMessage(GUILD, 0, 1, 0, 1, 1, 1, "CHAT_MSG_GUILD")
    ChatFrame2:FakeRefresh()
    T.eq(ChatFrame2.lines[1][1], GUILD, "the combat log: left as it is")
    local cf = ChatFrame1
    cf:AddMessage(GUILD, 0, 1, 0, 1, 1, 1, "CHAT_MSG_GUILD")
    cf:FakeRefresh()
    cf.lines[#cf.lines][1] = "someone else's rewrite"
    cf:FakeRefresh()
    T.eq(cf.lines[#cf.lines][1], "someone else's rewrite", "a line already looked at is never touched again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: short tags off, secret lines and locked-down chat: lines left as they are", function()
    login()
    local cf = ChatFrame1
    DaylightUI:Set("Chat", "shortTags", false)
    stub.RunTimers()
    cf:AddMessage(GUILD, 0, 1, 0, 1, 1, 1, "CHAT_MSG_GUILD")
    cf:FakeRefresh()
    T.eq(cf.lines[#cf.lines][1], GUILD, "off: left as it is")
    DaylightUI:Set("Chat", "shortTags", true)
    stub.RunTimers()
    cf.lines = {}
    cf:AddMessage(stub.Secret(GUILD), 1, 1, 1, 1, 1, 1, stub.Secret("CHAT_MSG_GUILD"))
    cf:FakeRefresh()
    T.truthy(issecretvalue(cf.lines[1][1]), "a secret line: untouched")
    -- In a raid fight the chat is locked down, so lines are left alone then and after.
    cf.lines = {}
    _G.IsInInstance = function() return true, "raid" end
    stub.combat = true
    cf:AddMessage(GUILD, 0, 1, 0, 1, 1, 1, "CHAT_MSG_GUILD")
    cf:FakeRefresh()
    T.eq(cf.lines[1][1], GUILD, "locked down: untouched")
    stub.combat, _G.IsInInstance = false, nil
    cf:FakeRefresh()
    T.eq(cf.lines[1][1], GUILD, "after the fight: it doesn't change under the player's eyes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: web links through a message filter, passed through when off", function()
    login()
    local f = filters.CHAT_MSG_SAY
    T.truthy(f and filters.CHAT_MSG_CHANNEL and filters.CHAT_MSG_WHISPER, "filters on the chat events")
    local Links = stub.chatModule.Links
    local hide, msg, author = f(ChatFrame1, "CHAT_MSG_SAY", "see https://x.com now", "Bob")
    T.eq(hide, false, "never hides a line")
    T.eq(msg, Links.Wrap("see https://x.com now"), "the address linked")
    T.truthy(string.find(msg, "|H" .. Links.PREFIX .. "https://x.com|h", 1, true))
    T.eq(author, "Bob", "the rest handed back as it was")
    T.eq(select("#", f(ChatFrame1, "CHAT_MSG_SAY", "no address here", "Bob")), 1, "nothing to link: the game's own")
    T.eq(select("#", f(ChatFrame1, "CHAT_MSG_SAY", stub.Secret("https://x.com"), "Bob")), 1, "secret: untouched")
    DaylightUI:Set("Chat", "links", false)
    stub.RunTimers()
    local r = { f(ChatFrame1, "CHAT_MSG_SAY", "see https://x.com now", "Bob") }
    T.eq(#r, 1, "off: passed through")
    T.eq(r[1], false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: fades after the idle time, panel and all; a new line or the mouse brings it back", function()
    login()
    local Chat = stub.chatModule.Chat
    local F = DaylightUI.Fade
    local holder = DaylightUIChat
    function holder:IsMouseOver() return stub.overChat == true end
    local function settle()
        Chat.UpdateFade()
        F.Step()
        for _ = 1, 120 do stub.RunOnUpdate(F.driver, 1 / 60) end
    end
    ChatFrame1:Show()
    Chat.Wake()
    settle()
    stub.Advance(DaylightUI:Get("Chat", "idleAfter") + 1)
    settle()
    T.eq(ChatFrame1:GetAlpha(), 0, "faded")
    T.eq(holder:GetAlpha(), 0, "the panel too")
    local focused = false
    function ChatFrame1EditBox:HasFocus() return focused end
    Chat.Step(1)
    T.eq(ChatFrame1EditBox:GetAlpha(), 0, "the input box unseen while not typing")
    focused = true
    Chat.Step(1)
    T.eq(ChatFrame1EditBox:GetAlpha(), 1, "and seen the moment you type")
    focused = false
    Chat.Step(1)
    stub.FireEvent("CHAT_MSG_SAY", "hi")
    settle()
    T.eq(ChatFrame1:GetAlpha(), 1, "a new line: back")
    stub.Advance(30)
    stub.overChat = true
    settle()
    T.eq(ChatFrame1:GetAlpha(), 1, "the mouse over it: stays")
    stub.overChat = nil
    DaylightUI:Set("Chat", "hides", "fights")
    stub.RunTimers()
    stub.Advance(60)
    settle()
    T.eq(ChatFrame1:GetAlpha(), 1, "hides only in fights: never fades")
end)

T.test("chat: floating, lines stay lineTime each; the mouse over the chat shows them all, leaving restarts their time", function()
    login()
    local Chat = stub.chatModule.Chat
    Chat.Pass()
    function DaylightUIChat:IsMouseOver() return stub.overChat == true end
    T.eq(ChatFrame1:GetTimeVisible(), 8, "8 s by default, not the game's 120")
    T.eq(ChatFrame3:GetTimeVisible(), 8, "a window out of the dock too")
    DaylightUI:Set("Chat", "lineTime", 20)
    stub.RunTimers()
    T.eq(ChatFrame2:GetTimeVisible(), 20, "the slider")
    DaylightUI:Set("Chat", "hides", "never")
    stub.RunTimers()
    Chat.UpdateFade()
    T.falsy(ChatFrame1:GetFading(), "the panel shown: lines stay, as the game's chat")
    DaylightUI:Set("Chat", "hides", "fights")
    Chat.fight = true
    Chat.UpdateFade()
    T.truthy(ChatFrame1:GetFading(), "a fight with Chat hides In fights: lines fade")
    Chat.fight = nil
    DaylightUI:Set("Chat", "hides", "always")
    stub.RunTimers()
    Chat.UpdateFade()
    T.truthy(ChatFrame1:GetFading(), "floating: lines fade at rest")
    stub.overChat = true
    Chat.UpdateFade()
    T.falsy(ChatFrame1:GetFading(), "the mouse over the chat: every line shown")
    local resets = ChatFrame1.fadeResets
    stub.overChat = nil
    Chat.UpdateFade()
    T.truthy(ChatFrame1:GetFading(), "left: they fade again")
    T.eq(ChatFrame1.fadeResets, resets + 1, "after their time again, not at once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: idle fade ignores loot and combat gains unless that's off", function()
    login()
    local Chat = stub.chatModule.Chat
    local F = DaylightUI.Fade
    function DaylightUIChat:IsMouseOver() return false end
    local function settle()
        Chat.UpdateFade()
        F.Step()
        for _ = 1, 120 do stub.RunOnUpdate(F.driver, 1 / 60) end
    end
    local function idleOut()
        stub.Advance(DaylightUI:Get("Chat", "idleAfter") + 1)
        settle()
    end
    ChatFrame1:Show()
    T.eq(DaylightUI:Get("Chat", "ignoreGains"), true, "on by default")
    idleOut()
    T.eq(ChatFrame1:GetAlpha(), 0, "faded")
    for _, e in ipairs(Chat.GAIN_EVENTS) do
        stub.FireEvent(e, "x")
        settle()
        T.eq(ChatFrame1:GetAlpha(), 0, e .. ": stays faded")
    end
    stub.FireEvent("CHAT_MSG_WHISPER", "hi", "Someone")
    settle()
    T.eq(ChatFrame1:GetAlpha(), 1, "a whisper still brings it back")
    DaylightUI:Set("Chat", "ignoreGains", false)
    stub.RunTimers()
    idleOut()
    T.eq(ChatFrame1:GetAlpha(), 0, "faded again")
    stub.FireEvent("CHAT_MSG_LOOT", "x")
    settle()
    T.eq(ChatFrame1:GetAlpha(), 1, "option off: loot brings it back")
end)

T.test("chat: typing a reply on the whisper card keeps the idle fade away", function()
    login()
    local CH = stub.chatModule
    local F = DaylightUI.Fade
    function DaylightUIChat:IsMouseOver() return false end
    local function settle()
        CH.Chat.UpdateFade()
        F.Step()
        for _ = 1, 120 do stub.RunOnUpdate(F.driver, 1 / 60) end
    end
    local function idleOut()
        stub.Advance(DaylightUI:Get("Chat", "idleAfter") + 1)
        settle()
    end
    stub.FireEvent("CHAT_MSG_WHISPER", "hi", "Someone", "", "", "", "", 0, 0, "", 0, 1, "Player-1-0001")
    CH.Convo.Open("w:Someone")
    T.truthy(CH.Convo.Key(), "the card is open")
    T.eq(_G.DaylightUIChatTalk:GetFrameStrata(), "HIGH", "the card sits over the action bars and unit frames (MEDIUM), as the Show window")
    local box, focused = CH.Convo.Thread().input, true
    box.HasFocus = function() return focused end    -- the fake game's boxes never hold focus
    T.truthy(CH.Convo.Typing())
    idleOut()
    T.eq(DaylightUIChat:GetAlpha(), 1, "typing a reply: the chat stays")
    focused = false
    T.falsy(CH.Convo.Typing())
    idleOut()
    T.eq(DaylightUIChat:GetAlpha(), 0, "not typing: idle fades it as before")
    box.HasFocus = nil
    CH.Convo.Close()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: idle fade wakes only for a line the selected tab shows", function()
    login()
    local Chat = stub.chatModule.Chat
    local F = DaylightUI.Fade
    function DaylightUIChat:IsMouseOver() return false end
    local function settle()
        Chat.UpdateFade()
        F.Step()
        for _ = 1, 120 do stub.RunOnUpdate(F.driver, 1 / 60) end
    end
    local function idleOut()
        stub.Advance(DaylightUI:Get("Chat", "idleAfter") + 1)
        settle()
    end
    local function channel(zone, base, name)
        stub.FireEvent("CHAT_MSG_CHANNEL", "hi", "Bob", "", name or "x", "Bob", "", zone, 1, base)
        settle()
    end
    ChatFrame1:Show()
    idleOut()
    T.eq(ChatFrame1:GetAlpha(), 0, "faded")
    -- ChatFrame2 is the selected tab; ChatFrame1 is another docked one.
    ChatFrame2:UnregisterEvent("CHAT_MSG_WHISPER")
    stub.FireEvent("CHAT_MSG_WHISPER", "hi", "Someone")
    settle()
    T.eq(ChatFrame1:GetAlpha(), 0, "a whisper the selected tab doesn't show: stays faded")
    ChatFrame2.channelList, ChatFrame2.zoneChannelList = { "General", "MyChannel" }, { 1, 0 }
    channel(2, "Trade", "2. Trade - City")
    T.eq(ChatFrame1:GetAlpha(), 0, "a channel the tab doesn't list: stays faded")
    channel(1, "General - Elwynn", "1. General - Elwynn")
    T.eq(ChatFrame1:GetAlpha(), 1, "a zone channel it lists: back")
    idleOut()
    channel(0, "mychannel")
    T.eq(ChatFrame1:GetAlpha(), 1, "a custom channel it lists, by name in any case: back")
    idleOut()
    channel(stub.Secret(3), stub.Secret("Trade"))
    T.eq(ChatFrame1:GetAlpha(), 1, "a channel line it can't read: counts as shown")
    idleOut()
    stub.FireEvent("CHAT_MSG_SAY", "hi")
    settle()
    T.eq(ChatFrame1:GetAlpha(), 1, "a kind the selected tab shows: back")
    DaylightUI:Set("Chat", "ignoreGains", false)
    stub.RunTimers()
    idleOut()
    ChatFrame2:UnregisterEvent("CHAT_MSG_LOOT")
    stub.FireEvent("CHAT_MSG_LOOT", "x")
    settle()
    T.eq(ChatFrame1:GetAlpha(), 0, "gains counted, but loot this tab doesn't show: stays faded")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: the panel's background can be turned off or made see-through", function()
    login()
    local panel = DaylightUIChatPanel
    DaylightUI:Set("general", "windowAlpha", 0.6)
    stub.RunTimers()
    T.eq(DaylightUI.Style.GetShell(panel).opts.bgAlpha, 0.6, "as solid as every window")
    DaylightUI:Set("Chat", "panelAlpha", 0.4)
    stub.RunTimers()
    T.eq(DaylightUI.Style.GetShell(panel).opts.bgAlpha, 0.6, "its own only with its switch")
    DaylightUI:Set("Chat", "panelAlphaOwn", true)
    stub.RunTimers()
    T.eq(DaylightUI.Style.GetShell(panel).opts.bgAlpha, 0.4, "as solid as set")
    DaylightUI:Set("Chat", "panelShown", false)
    stub.RunTimers()
    T.falsy(panel:IsShown(), "off: no panel")
end)

T.test("chat: the watcher never touches the chat's font or shadow once set (each rebuilds its lines, dropping link clicks)", function()
    login()
    local calls = 0
    local sf, so, sc = ChatFrame1.SetFont, ChatFrame1.SetShadowOffset, ChatFrame1.SetShadowColor
    function ChatFrame1:GetShadowOffset() return self.__sx or 0, self.__sy or 0 end
    function ChatFrame1:GetShadowColor() local c = self.__sc or {}; return c[1], c[2], c[3], c[4] end
    function ChatFrame1:SetShadowOffset(x, y) calls = calls + 1; self.__sx, self.__sy = x, y end
    function ChatFrame1:SetShadowColor(r, g, b, a) calls = calls + 1; self.__sc = { r, g, b, a } end
    function ChatFrame1:SetFont(...) calls = calls + 1; sf(self, ...) end
    DaylightUI:Set("Chat", "idleAfter", 20)   -- a refresh sets them once
    stub.RunTimers()
    local after = calls
    for _ = 1, 10 do stub.chatModule.Chat.Pass() end
    T.eq(calls, after, "not again on every look")
    DaylightUI:Set("Chat", "idleAfter", 25)
    stub.RunTimers()
    T.eq(calls, after, "nor on a refresh when nothing differs")
    ChatFrame1.SetFont, ChatFrame1.SetShadowOffset, ChatFrame1.SetShadowColor = sf, so, sc
end)

T.test("chat: the game's scroll bar stays out of sight; its jump arrow takes no clicks until our pill is over it", function()
    login()
    T.falsy(ChatFrame1.ScrollBar:IsShown(), "no scroll bar")
    T.falsy(ChatFrame1.ScrollToBottomButton:IsMouseEnabled(), "the arrow takes no clicks at rest")
end)

T.test("chat: a text size and outline for every window", function()
    local DUI = login()
    DUI:Set("Chat", "textSize", 16)
    DUI:Set("Chat", "outline", true)
    stub.RunTimers()
    T.eq(select(2, ChatFrame1:GetFont()), 16, "the size set")
    T.eq(select(3, ChatFrame1:GetFont()), "OUTLINE")
end)

T.test("chat: the input box and its \"Say:\" follow the text size, and go back at 0", function()
    local DUI = login()
    DUI:Set("Chat", "textSize", 18)
    DUI:Set("Chat", "outline", true)
    stub.RunTimers()
    T.eq(select(2, ChatFrame1EditBox:GetFont()), 18, "the typed text at the size set")
    T.eq(select(2, ChatFrame1EditBox.header:GetFont()), 18, "the header too")
    T.eq(select(3, ChatFrame1EditBox:GetFont()), "OUTLINE", "outlined like the lines")
    DUI:Set("Chat", "textSize", 0)
    DUI:Set("Chat", "outline", false)
    stub.RunTimers()
    T.eq(select(2, ChatFrame1EditBox:GetFont()), 14, "back to the game's own size")
    T.eq(select(2, ChatFrame1EditBox.header:GetFont()), 14)
    T.eq(select(3, ChatFrame1EditBox:GetFont()), "")
end)

T.test("chat: the typing box can open at the bottom", function()
    local DUI = login()
    DUI:Set("Chat", "inputAt", "bottom")
    stub.RunTimers()
    local p = ChatFrame1EditBox:GetPoint(1)
    T.eq(p, "BOTTOMLEFT")
    DUI:Set("Chat", "inputAt", "top")
    stub.RunTimers()
    T.eq((ChatFrame1EditBox:GetPoint(1)), "TOPLEFT")
end)

-- The IM chat style types in each tab's own box. Every docked tab's box sits
-- where the main one does, at the panel's width, and is only seen while typing.
-- A window out of the dock keeps its box under itself.
T.test("chat: every docked tab's typing box follows the panel", function()
    local DUI = login()
    stub.RunTimers()
    local Chat = stub.chatModule.Chat
    local function same(a, b)
        for i = 1, 2 do
            local p1, r1, rp1, x1, y1 = a:GetPoint(i)
            local p2, r2, rp2, x2, y2 = b:GetPoint(i)
            if p1 ~= p2 or r1 ~= r2 or rp1 ~= rp2 or x1 ~= x2 or y1 ~= y2 then return false end
        end
        return a:GetNumPoints() == 2 and b:GetNumPoints() == 2
    end
    T.truthy(same(ChatFrame2EditBox, ChatFrame1EditBox), "a docked tab's box in the main one's spot")
    T.falsy(select(2, ChatFrame3EditBox:GetPoint(1)) == DaylightUIChatPanel, "an undocked window's box left alone")
    DUI:Set("Chat", "inputAt", "bottom")
    stub.RunTimers()
    T.truthy(same(ChatFrame2EditBox, ChatFrame1EditBox), "and it moves with the setting")
    local focused = false
    function ChatFrame2EditBox:HasFocus() return focused end
    ChatFrame2EditBox:SetAlpha(0.35)             -- the game's look for a box not being typed in
    Chat.Step(1)
    T.eq(ChatFrame2EditBox:GetAlpha(), 0, "unseen while not typing")
    focused = true
    Chat.Step(1)
    T.eq(ChatFrame2EditBox:GetAlpha(), 1, "seen while typing in it")
    focused = false
    Chat.Step(1)
    ChatFrame2.isDocked = false
    Chat.Pass()
    T.eq(select(2, ChatFrame2EditBox:GetPoint(1)), ChatFrame2, "pulled out of the dock: back under its window")
    T.eq(ChatFrame2EditBox:GetAlpha(), 1, "and the game's to show")
end)

T.test("chat: the typing box can open under the panel, with room kept for it", function()
    local DUI = login()
    stub.RunTimers()
    local h = DaylightUIChat:GetHeight()
    DUI:Set("Chat", "inputAt", "below")
    stub.RunTimers()
    local p, rel = ChatFrame1EditBox:GetPoint(1)
    T.eq(p, "BOTTOMLEFT")
    T.eq(rel, DaylightUIChat, "under the whole corner block, not inside the panel")
    T.eq(DaylightUIChat:GetHeight(), h + stub.chatModule.Chat.GAP + stub.chatModule.Chat.TAB_ROOM,
        "the block grows to keep a strip for it")
    DUI:Set("Chat", "inputAt", "bottom")
    stub.RunTimers()
    local _, rel2 = ChatFrame1EditBox:GetPoint(1)
    T.eq(rel2, DaylightUIChatPanel, "back inside the panel")
    T.eq(DaylightUIChat:GetHeight(), h, "and the strip gone")
end)

T.test("chat: speech bubbles get our look; a forbidden one (an instance) is left alone", function()
    login()
    local b1 = CreateFrame("Frame", nil, UIParent)
    local art = CreateFrame("Frame", nil, b1)   -- a bubble's art and text are on its child
    local tex = art:CreateTexture()
    tex:SetTexture("bubble art")
    local fs = art:CreateFontString()
    fs:SetFont("GameFont", 12, "")
    local b2 = CreateFrame("Frame", nil, UIParent)
    b2.__forbidden = true
    stub.SetBubbles({ b1, b2 })
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    T.eq(tex.__texture, nil, "the bubble's own art cleared")
    T.eq(fs:GetFont(), DaylightUI.Style.FONT, "our font")
    T.truthy(DaylightUI.Style.GetShell(art), "our shell")
    T.isnil(DaylightUI.Style.GetShell(b2), "forbidden: left alone")
end)

T.test("chat: speech bubbles can be turned off", function()
    local DUI = login()
    DUI:Set("Chat", "bubbles", false)
    local b1 = CreateFrame("Frame", nil, UIParent)
    local art = CreateFrame("Frame", nil, b1)
    art:CreateTexture():SetTexture("art")
    stub.SetBubbles({ b1 })
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    T.isnil(DaylightUI.Style.GetShell(art), "off: not skinned")
end)

T.test("chat: history is saved at logout, newest lines only, secret and combat log lines left out", function()
    local DUI = login()
    DaylightUI:Set("Chat", "historyLines", 20)
    stub.RunTimers()
    for i = 1, 30 do ChatFrame1:AddMessage("line " .. i, 1, 0.5, 0) end
    ChatFrame1:AddMessage(stub.Secret("hidden"), 1, 1, 1)
    ChatFrame2:AddMessage("combat log line", 1, 1, 1)
    stub.FireEvent("PLAYER_LOGOUT")
    local saved = DUI.DB.Character().chatHistory
    T.truthy(saved, "saved")
    T.eq(saved.savedAt, time())
    local lines = saved.frames.ChatFrame1
    T.eq(#lines, 20, "only the newest 20")
    T.eq(lines[1][1], "line 11"); T.eq(lines[20][1], "line 30")
    T.eq(lines[20][3], 0.5, "with its color")
    T.eq(saved.frames.ChatFrame2, nil, "the combat log isn't kept")
end)

T.test("chat: history comes back after a reload, under a divider, once", function()
    local DUI = login()
    local History = stub.chatModule.History
    DUI.DB.Character().chatHistory = { savedAt = time() - 10,
        frames = { ChatFrame1 = { { "old one", 1, 1, 1 }, { "old two", 1, 0, 0 } } } }
    ChatFrame1.lines = {}
    T.eq(History.Restore(DaylightUI:GetModule("Chat").db), 2)
    T.eq(ChatFrame1.lines[1][1], "old one")
    T.eq(ChatFrame1.lines[2][1], "old two"); T.eq(ChatFrame1.lines[2][3], 1)
    T.eq(ChatFrame1.lines[3][1], History.DIVIDER, "a divider after the old lines")
    T.eq(DUI.DB.Character().chatHistory, nil, "used up")
    T.eq(History.Restore(DaylightUI:GetModule("Chat").db), 0, "not twice")
end)

T.test("chat: with Also after logging out off, an old save isn't replayed; nothing is saved with history off", function()
    local DUI = login()
    local History = stub.chatModule.History
    DaylightUI:Set("Chat", "historyLogout", false)
    stub.RunTimers()
    DUI.DB.Character().chatHistory = { savedAt = time() - History.MAX_AGE - 1,
        frames = { ChatFrame1 = { { "yesterday", 1, 1, 1 } } } }
    ChatFrame1.lines = {}
    T.eq(History.Restore(DaylightUI:GetModule("Chat").db), 0)
    T.eq(#ChatFrame1.lines, 0)
    DaylightUI:Set("Chat", "history", false)
    stub.RunTimers()
    ChatFrame1:AddMessage("x", 1, 1, 1)
    stub.FireEvent("PLAYER_LOGOUT")
    T.eq(DUI.DB.Character().chatHistory, nil, "off: nothing saved")
end)

T.test("chat: after a logout, history comes back under a last-session line with its time", function()
    local DUI = login()
    local History = stub.chatModule.History
    local before = time()
    stub.SetTime(os.time({ year = 2026, month = 10, day = 5, hour = 21, min = 30 }))
    local savedAt = time() - 600     -- 21:20 the same day, past the reload window
    DUI.DB.Character().chatHistory = { savedAt = savedAt,
        frames = { ChatFrame1 = { { "from before", 1, 1, 1 } } } }
    ChatFrame1.lines = {}
    T.eq(History.Restore(DaylightUI:GetModule("Chat").db), 1)
    T.eq(ChatFrame1.lines[1][1], "from before")
    T.eq(ChatFrame1.lines[2][1], "|cffc2b59e-- last session, 21:20 --|r")
    local earlier = os.time({ year = 2026, month = 10, day = 2, hour = 21, min = 20 })
    T.eq(History.SessionDivider(earlier), "|cffc2b59e-- last session, 02 Oct 21:20 --|r",
        "another day: with the date")
    stub.SetTime(before)
end)

T.test("chat: the divider and Battle.net name lines aren't saved again", function()
    local DUI = login()
    local History = stub.chatModule.History
    ChatFrame1.lines = {}
    ChatFrame1:AddMessage(History.DIVIDER, 1, 1, 1)
    ChatFrame1:AddMessage(History.SessionDivider(time() - 600), 1, 1, 1)
    ChatFrame1:AddMessage("|Kq12|k says hi", 1, 1, 1)
    ChatFrame1:AddMessage("|cff" .. "808080-- before reload --|r", 1, 1, 1)   -- an old gray one, saved before
    ChatFrame1:AddMessage("kept", 1, 1, 1)
    stub.FireEvent("PLAYER_LOGOUT")
    local lines = DUI.DB.Character().chatHistory.frames.ChatFrame1
    T.eq(#lines, 1); T.eq(lines[1][1], "kept")
end)

T.test("chat: copy text is plain: no colors, links shown as their words, no icons", function()
    login()
    local Copy = stub.chatModule.Copy
    T.eq(Copy.Plain("|cffff0000red|r text"), "red text")
    T.eq(Copy.Plain("buy |cff1eff00|Hitem:1::|h[Sword]|h|r now"), "buy [Sword] now")
    T.eq(Copy.Plain("|TInterface/Icons/x:14|t gold"), " gold")
    T.eq(Copy.Plain("|Afriend-icon:12:12|a hi"), " hi")
    T.eq(Copy.Plain("a || b"), "a | b", "an escaped bar stays a bar")
end)

T.test("chat: the copy window holds the tab's lines, secret ones left out", function()
    login()
    local Copy = stub.chatModule.Copy
    ChatFrame1.lines = {}
    ChatFrame1:AddMessage("|cffffffffone|r", 1, 1, 1)
    ChatFrame1:AddMessage(stub.Secret("x"), 1, 1, 1)
    ChatFrame1:AddMessage("two", 1, 1, 1)
    local want = "|cffffffff|cffffffffone|r|r\n|cffffffff two|r"
    ChatFrame1.lines = {}
    ChatFrame1:AddMessage("|cffffffffone|r", 1, 1, 1)
    ChatFrame1:AddMessage(stub.Secret("x"), 1, 1, 1)
    ChatFrame1:AddMessage("|Hitem:1|h two|h", 1, 1, 1)
    T.eq(Copy.Text(ChatFrame1), want, "chat colors kept, links as words")
    Copy.Show(ChatFrame1)
    local box = _G.DaylightUIChatCopy
    T.truthy(box:IsShown(), "shown")
    T.eq(box.edit.__text, want)
end)

T.test("chat: the copy window opens at the newest lines, once the game has measured the text", function()
    login()
    local Copy = stub.chatModule.Copy
    ChatFrame1.lines = {}
    ChatFrame1:AddMessage("one", 1, 1, 1)
    Copy.Show(ChatFrame1)
    local area = _G.DaylightUIChatCopy.area
    -- The game measures the new text a frame later and reports the new range.
    area:GetScript("OnScrollRangeChanged")(area, 0, 500)
    T.eq(area:GetVerticalScroll(), 500, "at the bottom")
end)

T.test("chat: the copy window keeps the cursor in view and scrolls while a selection is dragged past its top", function()
    login()
    local Copy = stub.chatModule.Copy
    ChatFrame1.lines = {}
    ChatFrame1:AddMessage("one", 1, 1, 1)
    Copy.Show(ChatFrame1)
    local area = _G.DaylightUIChatCopy.area
    local edit = area.edit
    area:SetHeight(200)
    area.GetVerticalScrollRange = function() return 1000 end
    area:SetVerticalScroll(600)
    -- The cursor moved to a line above the view (keys, or a selection's end).
    edit:GetScript("OnCursorChanged")(edit, 0, -100, 1, 14)
    T.eq(area:GetVerticalScroll(), 100, "scrolled up to the cursor's line")
    edit:GetScript("OnCursorChanged")(edit, 0, -150, 1, 14)
    T.eq(area:GetVerticalScroll(), 100, "already in view: stays")
    -- Dragging a selection with the mouse above the box scrolls on up.
    local down = _G.IsMouseButtonDown
    _G.IsMouseButtonDown = function() return true end
    area.GetTop = function() return 500 end
    area.GetBottom = function() return 300 end
    stub.cursorPos = { 0, 540 * area:GetEffectiveScale() }
    edit:GetScript("OnMouseDown")(edit, "LeftButton")
    local tick = area:GetScript("OnUpdate")
    T.truthy(tick, "a driver only while dragging")
    tick(area, 0.1)
    T.truthy(area:GetVerticalScroll() < 100, "scrolling up")
    _G.IsMouseButtonDown = function() return false end
    tick(area, 0.1)
    T.isnil(area:GetScript("OnUpdate"), "stops once the button is up")
    _G.IsMouseButtonDown = down
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: /dui copy opens the selected tab; the button can be turned off", function()
    login()
    _G.FCFDock_GetSelectedWindow = function() return ChatFrame1 end
    ChatFrame1.lines = {}
    ChatFrame1:AddMessage("hello", 1, 1, 1)
    DaylightUI.RunCommand("copy")
    T.eq(_G.DaylightUIChatCopy.edit.__text, "|cffffffffhello|r")
    local Copy = stub.chatModule.Copy
    T.truthy(Copy.Button(), "the Copy link exists")
    Copy.SetNear(true)
    T.truthy(Copy.Button():IsShown(), "shown with the mouse over the chat")
    DaylightUI:Set("Chat", "copyButton", false)
    stub.RunTimers()
    Copy.SetNear(true)
    T.falsy(Copy.Button():IsShown(), "off: never shown")
end)

-- GameTooltip as the tests need it: who owns it, what it shows.
local function fakeTooltip()
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    function tip:SetOwner(o, a) self.owner, self.anchor = o, a end
    function tip:GetOwner() return self.owner end
    function tip:SetHyperlink(l) self.link = l end
    tip:Hide()
    return tip
end

T.test("chat: a link's tooltip shows above the chat panel on mouseover and goes on leaving", function()
    login()
    local tip = fakeTooltip()
    callbacks["ChatFrame.OnHyperlinkEnter"](ChatFrame1, "item:19019:0", "[Thunderfury]")
    T.eq(tip.link, "item:19019:0")
    T.eq(tip.owner, ChatFrame1)
    T.truthy(tip:IsShown(), "shown")
    local point, rel, relPoint = tip:GetPoint(1)
    T.eq(point, "BOTTOMLEFT"); T.eq(relPoint, "TOPLEFT")
    T.eq(rel, _G.DaylightUIChatPanel, "on the corner panel's top edge")
    callbacks["ChatFrame.OnHyperlinkLeave"](ChatFrame1)
    T.falsy(tip:IsShown(), "hidden on leave")
    -- A window pulled out of the dock uses its own panel, not the corner one.
    callbacks["ChatFrame.OnHyperlinkEnter"](ChatFrame3, "spell:133")
    local _, rel3 = tip:GetPoint(1)
    T.truthy(rel3 ~= _G.DaylightUIChatPanel, "not the corner panel")
    T.eq(rel3:GetParent(), ChatFrame3, "the pulled-out window's own panel")
    _G.GameTooltip = nil
end)

T.test("chat: no link tooltip for a secret link, an unknown type, or with it off; others' tooltips stay", function()
    login()
    local tip = fakeTooltip()
    callbacks["ChatFrame.OnHyperlinkEnter"](ChatFrame1, stub.Secret("item:1"))
    callbacks["ChatFrame.OnHyperlinkEnter"](ChatFrame1, "addon:DaylightUI:url:example.com")
    T.isnil(tip.link, "nothing shown")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    DaylightUI:Set("Chat", "linkTooltips", false)
    stub.RunTimers()
    callbacks["ChatFrame.OnHyperlinkEnter"](ChatFrame1, "item:1")
    T.isnil(tip.link, "off: nothing")
    tip:SetOwner(UIParent); tip:Show()
    callbacks["ChatFrame.OnHyperlinkLeave"](ChatFrame1)
    T.truthy(tip:IsShown(), "someone else's tooltip stays up")
    _G.GameTooltip = nil
end)

T.test("chat: a link's tooltip goes next to the chat, at the mouse, or at the Tooltip handle", function()
    login()
    local tip = fakeTooltip()
    DaylightUI:Set("Chat", "linkTooltipSpot", "cursor")
    stub.RunTimers()
    callbacks["ChatFrame.OnHyperlinkEnter"](ChatFrame1, "item:1")
    T.eq(tip.anchor, "ANCHOR_CURSOR", "at the mouse")
    callbacks["ChatFrame.OnHyperlinkLeave"](ChatFrame1)
    -- The handle wins even when the Tooltips page follows the cursor.
    local handle = CreateFrame("Frame", "DaylightUITooltipAnchor", UIParent)
    DaylightUI:Set("Chat", "linkTooltipSpot", "game")
    stub.RunTimers()
    callbacks["ChatFrame.OnHyperlinkEnter"](ChatFrame1, "item:1")
    local point, rel = tip:GetPoint(1)
    T.eq(point, "BOTTOMRIGHT"); T.eq(rel, handle, "on the unlock handle")
    T.eq(tip.owner, ChatFrame1, "still ours, so leaving hides it")
    callbacks["ChatFrame.OnHyperlinkLeave"](ChatFrame1)
    T.falsy(tip:IsShown(), "hidden on leave")
    _G.DaylightUITooltipAnchor = nil
    _G.GameTooltip = nil
end)

T.test("chat: a tall compare never hangs over the chat lines", function()
    login()
    local tip = fakeTooltip()
    tip:SetHeight(100)
    -- The game hangs a compare from the tooltip's top edge (TooltipComparisonManager).
    local shop = CreateFrame("GameTooltip", "ShoppingTooltip1", UIParent)
    shop:SetHeight(160)
    shop:Hide()
    tip.shoppingTooltips = { shop }
    callbacks["ChatFrame.OnHyperlinkEnter"](ChatFrame1, "item:1")
    local LinkTips = stub.chatModule.LinkTips
    LinkTips.Lift()
    local _, _, _, _, y = tip:GetPoint(1)
    T.eq(y, stub.chatModule.Chat.GAP, "no compare: right on the panel")
    shop:Show()     -- Shift, or the game's own setting, a moment later
    LinkTips.Lift()
    _, _, _, _, y = tip:GetPoint(1)
    T.eq(y, stub.chatModule.Chat.GAP + 60, "stands higher by the difference")
    shop:Hide()
    LinkTips.Lift()
    _, _, _, _, y = tip:GetPoint(1)
    T.eq(y, stub.chatModule.Chat.GAP, "back down when it goes")
    callbacks["ChatFrame.OnHyperlinkLeave"](ChatFrame1)
    _G.GameTooltip = nil
end)

T.test("chat: a link's compare can wait for Shift", function()
    login()
    local tip = fakeTooltip()
    local suppressed
    _G.GameTooltip_SuppressAutomaticCompareItem = function(t) suppressed = t end
    callbacks["ChatFrame.OnHyperlinkEnter"](ChatFrame1, "item:1")
    T.isnil(suppressed, "on: as the game's setting says")
    callbacks["ChatFrame.OnHyperlinkLeave"](ChatFrame1)
    DaylightUI:Set("Chat", "linkTooltipCompare", false)
    stub.RunTimers()
    callbacks["ChatFrame.OnHyperlinkEnter"](ChatFrame1, "item:1")
    T.eq(suppressed, tip, "off: only Shift compares")
    callbacks["ChatFrame.OnHyperlinkLeave"](ChatFrame1)
    _G.GameTooltip_SuppressAutomaticCompareItem = nil
    _G.GameTooltip = nil
end)

T.test("chat: the hover delay waits, and leaving the link cancels it", function()
    login()
    local tip = fakeTooltip()
    DaylightUI:Set("Chat", "linkTooltipDelay", 0.3)
    stub.RunTimers()
    callbacks["ChatFrame.OnHyperlinkEnter"](ChatFrame1, "item:1")
    T.isnil(tip.link, "nothing yet")
    stub.RunTimers()
    T.eq(tip.link, "item:1", "shown once it's waited")
    callbacks["ChatFrame.OnHyperlinkLeave"](ChatFrame1)
    tip.link = nil
    callbacks["ChatFrame.OnHyperlinkEnter"](ChatFrame1, "item:2")
    callbacks["ChatFrame.OnHyperlinkLeave"](ChatFrame1)
    stub.RunTimers()
    T.isnil(tip.link, "swept across it: nothing shows")
    _G.GameTooltip = nil
end)

-- The game's sound calls as the tests need them: what played, what's muted.
local function soundFakes()
    local played, muted = {}, {}
    _G.PlaySoundFile = function(path, channel) played[#played + 1] = { path, channel } end
    _G.MuteSoundFile = function(id) muted[id] = true end
    _G.UnmuteSoundFile = function(id) muted[id] = nil end
    return played, muted
end

local function noSoundFakes() _G.PlaySoundFile, _G.MuteSoundFile, _G.UnmuteSoundFile = nil, nil, nil end

T.test("chat: a whisper plays our soft sound, at most every few seconds, with the game's muted", function()
    local played, muted
    local DUI = login(function() played, muted = soundFakes() end)
    local W = stub.chatModule.Whisper
    for k in pairs(played) do played[k] = nil end      -- the setup guide's open sound at login (Sound.lua)
    -- Muted at every login, since after a game restart the saved flag alone mutes nothing.
    T.truthy(muted[W.GAME_FILE], "the game's whisper sound muted at login")
    T.truthy(DUI.DB.Root().tellMuted, "remembered as ours")
    stub.FireEvent("CHAT_MSG_WHISPER", "hi", "Someone")
    T.eq(#played, 1); T.eq(played[1][1], W.SOUNDS.soft, "Breath by default"); T.eq(played[1][2], "SFX")
    stub.FireEvent("CHAT_MSG_WHISPER", "again", "Someone")
    T.eq(#played, 1, "not twice inside the cooldown")
    stub.Advance(W.COOLDOWN + 1)
    stub.FireEvent("CHAT_MSG_BN_WHISPER", stub.Secret("hey"), stub.Secret("Friend"))
    T.eq(#played, 2, "a Battle.net whisper, secret parts and all")
    stub.Advance(W.COOLDOWN + 1)
    stub.FireEvent("CHAT_MSG_WHISPER_INFORM", "sent", "Someone")
    T.eq(#played, 2, "not for whispers you send")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    noSoundFakes()
end)

T.test("chat: whisper sound None is silent, The game's own lifts our mute, picking Soft plays it once", function()
    local played, muted
    local DUI = login(function() played, muted = soundFakes() end)
    local W = stub.chatModule.Whisper
    for k in pairs(played) do played[k] = nil end      -- the setup guide's open sound at login (Sound.lua)
    DaylightUI:Set("Chat", "whisperSound", "none")
    stub.RunTimers()
    stub.FireEvent("CHAT_MSG_WHISPER", "hi", "Someone")
    T.eq(#played, 0, "none: silent")
    T.truthy(muted[W.GAME_FILE], "none: the game's stays muted")
    DaylightUI:Set("Chat", "whisperSound", "game")
    stub.RunTimers()
    T.isnil(muted[W.GAME_FILE], "the game's sound back")
    T.isnil(DUI.DB.Root().tellMuted, "nothing of ours left muted")
    stub.Advance(W.COOLDOWN + 1)
    stub.FireEvent("CHAT_MSG_WHISPER", "hi", "Someone")
    T.eq(#played, 0, "game: ours stays quiet, the game plays its own")
    muted[W.GAME_FILE] = true      -- another addon mutes it
    DaylightUI:Set("Chat", "linkTooltips", false)
    stub.RunTimers()
    T.truthy(muted[W.GAME_FILE], "another addon's mute isn't lifted")
    DaylightUI:Set("Chat", "whisperSound", "soft")
    stub.RunTimers()
    T.eq(#played, 1, "picked in the options: heard once")
    T.truthy(muted[W.GAME_FILE], "and the game's muted again")
    noSoundFakes()
end)

-- An item on the chat options page, by its label.
local function chatItem(label)
    for _, page in ipairs(stub.chatModule.OPTIONS.pages) do
        for _, g in ipairs(page.groups) do
            for _, it in ipairs(g.items) do if it.label == label then return it end end
        end
    end
end

T.test("chat: every soft whisper sound can be picked, and Play plays the one picked, cooldown or not", function()
    local played
    login(function() played = soundFakes() end)
    local W = stub.chatModule.Whisper
    local item = chatItem("Whisper sound")
    for _, k in ipairs({ "dewdrop", "hello", "bell", "pop" }) do
        T.truthy(item.values[k], k .. " in the list")
        T.truthy(W.SOUNDS[k], k .. " has a file")
    end
    T.eq(item.order[1], "soft", "Breath first")
    DaylightUI:Set("Chat", "whisperSound", "hello")
    stub.RunTimers()
    T.eq(played[#played][1], W.SOUNDS.hello, "picked: heard once")
    stub.Advance(W.COOLDOWN + 1)
    stub.FireEvent("CHAT_MSG_WHISPER", "hi", "Someone")
    T.eq(played[#played][1], W.SOUNDS.hello, "a whisper plays the one picked")
    local n = #played
    local play = chatItem("Play whisper sound")
    play.func()
    T.eq(#played, n + 1, "inside the cooldown, Play still plays")
    local get = function(k) return DaylightUI:Get("Chat", k) end
    T.falsy(play.disabled(get), "something to play")
    DaylightUI:Set("Chat", "whisperSound", "none")
    stub.RunTimers()
    T.truthy(play.disabled(get), "None: nothing to play")
    noSoundFakes()
end)

T.test("chat: with The game's own picked, Play plays the game's whisper sound", function()
    local kits = {}
    login(function()
        soundFakes()
        _G.SOUNDKIT = { TELL_MESSAGE = 3081 }
        _G.PlaySound = function(id, channel) kits[#kits + 1] = id end
    end)
    DaylightUI:Set("Chat", "whisperSound", "game")
    stub.RunTimers()
    chatItem("Play whisper sound").func()
    T.eq(kits[1], 3081)
    _G.SOUNDKIT, _G.PlaySound = nil, nil
    noSoundFakes()
end)

-- The chat box as the recall tests need it: its alt-arrow mode, keys and sends.
local function arrowBox(eb)
    eb.altMode = true
    function eb:SetAltArrowKeyMode(on) self.altMode = on end
    function eb:GetAltArrowKeyMode() return self.altMode end
end
local function key(eb, k) eb:GetScript("OnKeyDown")(eb, k) end
local function send(eb, text)
    eb:SetText(text)
    callbacks["ChatFrame.OnEditBoxPreSendText"](eb)
    eb:SetText("")
end

T.test("chat: Up and Down bring back sent lines, Down past the newest gives back the draft", function()
    login(function() arrowBox(ChatFrame1EditBox) end)
    local eb = ChatFrame1EditBox
    T.eq(eb.altMode, false, "plain arrows reach the box")
    send(eb, "first"); send(eb, "second")
    eb:SetText("half typ")
    key(eb, "UP");   T.eq(eb:GetText(), "second")
    key(eb, "UP");   T.eq(eb:GetText(), "first")
    key(eb, "UP");   T.eq(eb:GetText(), "first", "stops at the oldest")
    key(eb, "DOWN"); T.eq(eb:GetText(), "second")
    key(eb, "DOWN"); T.eq(eb:GetText(), "half typ", "the draft back")
    -- A recalled line edited, then Up: a fresh start, with the edit kept as the draft.
    key(eb, "UP");   T.eq(eb:GetText(), "second")
    eb:SetText("second, edited")
    key(eb, "UP");   T.eq(eb:GetText(), "second", "newest again")
    key(eb, "DOWN"); T.eq(eb:GetText(), "second, edited", "your edit back")
    DaylightUI:Set("Chat", "arrowHistory", false)
    stub.RunTimers()
    T.eq(eb.altMode, true, "off: the box's own mode back")
    eb:SetText("x"); key(eb, "UP")
    T.eq(eb:GetText(), "x", "off: arrows left alone")
end)

-- A whisper tab (a temporary window) has its own box, and Up and Down work there too.
T.test("chat: a whisper tab's own box recalls sent lines too", function()
    login(function()
        ChatFrame3.isTemporary = true
        arrowBox(ChatFrame3EditBox)
    end)
    local eb = ChatFrame3EditBox
    T.eq(eb.altMode, false, "plain arrows reach the whisper tab's box")
    send(eb, "hi there")
    T.truthy(eb:GetScript("OnKeyDown"), "its keys are heard")
    key(eb, "UP")
    T.eq(eb:GetText(), "hi there")
end)

T.test("chat: recall skips empty, secret, protected and repeated lines, keeps 50, leaves Alt and secrets alone", function()
    local alt = false
    login(function()
        arrowBox(ChatFrame1EditBox)
        _G.IsAltKeyDown = function() return alt end
        _G.IsSecureCmd = function(c) return c == "/cast" end
    end)
    local eb = ChatFrame1EditBox
    local R = stub.chatModule.Recall
    send(eb, ""); send(eb, "/cast Fireball"); send(eb, "hello"); send(eb, "hello")
    T.eq(#R.Lines(), 1, "one hello, nothing else")
    eb:SetText(stub.Secret("hidden"))
    callbacks["ChatFrame.OnEditBoxPreSendText"](eb)
    T.eq(#R.Lines(), 1, "a secret line isn't read")
    for i = 1, 60 do send(eb, "line " .. i) end
    T.eq(#R.Lines(), R.MAX); T.eq(R.Lines()[1], "line 11", "the oldest dropped")
    -- A Battle.net whisper reply has secret box text, so it's left alone.
    eb:SetText(stub.Secret("reply"))
    key(eb, "UP")
    T.truthy(issecretvalue(eb:GetText()), "the secret text stays")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    eb:SetText("typing"); alt = true; key(eb, "UP")
    T.eq(eb:GetText(), "typing", "Alt+Up is the game's own")
    _G.IsAltKeyDown, _G.IsSecureCmd = nil, nil
end)

-- The game runs a slash command and empties the box before its "about to send"
-- call (ParseText, then OnPreSendText), so only Enter sees "/dance".
T.test("chat: Up brings back a slash command you sent, once", function()
    login(function()
        arrowBox(ChatFrame1EditBox)
        _G.IsSecureCmd = function(c) return c == "/cast" end
    end)
    local eb = ChatFrame1EditBox
    local R = stub.chatModule.Recall
    -- /dance is run and cleared by the game, with no pre-send call.
    eb:SetText("/dance"); key(eb, "ENTER"); eb:SetText("")
    -- /s hi: the game turns it into "hi" in say, then makes the pre-send call.
    eb:SetText("/s hi"); key(eb, "ENTER"); eb:SetText("hi")
    callbacks["ChatFrame.OnEditBoxPreSendText"](eb); eb:SetText("")
    eb:SetText("/cast Fireball"); key(eb, "ENTER"); eb:SetText("")
    T.eq(#R.Lines(), 2, "/dance and /s hi, no /cast, no bare hi")
    key(eb, "UP"); T.eq(eb:GetText(), "/s hi")
    key(eb, "UP"); T.eq(eb:GetText(), "/dance")
    _G.IsSecureCmd = nil
end)

T.test("chat: in chat lockdown recall pauses, says so once, and leaves the box alone", function()
    login(function() arrowBox(ChatFrame1EditBox) end)
    local eb = ChatFrame1EditBox
    eb.chatFrame = ChatFrame1
    _G.C_ChatInfo = _G.C_ChatInfo or {}
    local prev, locked = C_ChatInfo.InChatMessagingLockdown, true
    C_ChatInfo.InChatMessagingLockdown = function() return locked end
    send(eb, "hello")
    ChatFrame1.lines = {}
    eb:SetText("draft"); key(eb, "UP"); key(eb, "UP")
    T.eq(eb:GetText(), "draft", "nothing recalled")
    T.eq(#ChatFrame1.lines, 1, "one notice, not two")
    T.eq(ChatFrame1.lines[1][1], stub.chatModule.Recall.NOTICE)
    locked = false
    key(eb, "UP")
    T.eq(eb:GetText(), "hello", "back once it lifts")
    C_ChatInfo.InChatMessagingLockdown = prev
end)

T.test("chat: old fade settings move over before the module merges its defaults", function()
    local p = { general = { oocAlpha = 0.3 },
                modules = { Chat = { fade = false, fadeAfter = 20, fadeOOC = true } } }
    local DUI = stub.Load({ chat = true })
    DUI.FadeUpgrade.Run(p)
    local c = p.modules.Chat
    T.eq(c.hides, "fightsIdle", "idle off but fading out of combat: hides in fights and when idle")
    T.isnil(c.idleFade)
    T.eq(c.idleAfter, 20)
    T.isnil(c.fade.mode, "Chat hides does the fading now"); T.isnil(c.fade.alpha)
    T.isnil(c.fadeAfter); T.isnil(c.fadeOOC)
    local m = { general = {}, modules = { Chat = { mouseoverOnly = true } } }
    DUI.FadeUpgrade.Run(m)
    T.eq(m.modules.Chat.hides, "fightsIdle"); T.isnil(m.modules.Chat.fade.mode)
    T.isnil(m.modules.Chat.mouseoverOnly)
end)

T.test("chat: its four ways to hide become one Chat hides pick", function()
    local DUI = stub.Load({ chat = true })
    local function up(chat)
        local p = { general = { fadeEngine = 6 }, modules = { Chat = chat } }
        DUI.FadeUpgrade.Run(p)
        return p.modules.Chat
    end
    T.eq(up({}).hides, "fightsIdle", "the old defaults: fights and idle")
    T.eq(up({ hides = "always" }).hides, "always", "a new profile's pick (the standard start floats) stays")
    T.eq(up({ floating = true, idleFade = false }).hides, "always", "Floating chat")
    T.eq(up({ idleFade = false }).hides, "fights", "fights only")
    T.eq(up({ idleFade = false, combatFloat = false }).hides, "never", "neither")
    T.eq(up({ idleFade = false, combatFloat = false, fade = { mode = "combat" } }).hides, "fights")
    local c = up({ idleFade = false, combatFloat = false, floating = false, fade = { mode = "always", opacity = 0.8 } })
    T.eq(c.hides, "fightsIdle", "a fade out of fights: idle")
    T.eq(c.fade.opacity, 0.8, "its opacity stays"); T.isnil(c.fade.mode)
    T.isnil(c.floating); T.isnil(c.combatFloat); T.isnil(c.idleFade)
end)

-- ---------------------------------------------------------------------
-- No repeated work (each test counts the work it saves)
-- ---------------------------------------------------------------------

T.test("chat: the watcher reuses one window list and asks about the mouse once", function()
    login()
    local Chat = stub.chatModule.Chat
    local list = Chat.Frames()
    T.eq(#list, 3)
    T.eq(Chat.Frames(), list, "the same list each pass, not a new one")
    T.eq(#Chat.Frames(), 3, "filled afresh")
    local asks = 0
    function DaylightUIChat:IsMouseOver() asks = asks + 1; return false end
    Chat.UpdateFade()
    T.eq(asks, 1)
end)

T.test("chat: with idle fade off, new lines aren't looked at; switched on, its clock starts then", function()
    local DUI = login()
    local Chat = stub.chatModule.Chat
    local F = DaylightUI.Fade
    function DaylightUIChat:IsMouseOver() return false end
    local function settle()
        Chat.UpdateFade()
        F.Step()
        for _ = 1, 120 do stub.RunOnUpdate(F.driver, 1 / 60) end
    end
    local asked = 0
    local shows = Chat.Shows
    Chat.Shows = function(...) asked = asked + 1; return shows(...) end
    stub.FireEvent("CHAT_MSG_SAY", "hi")
    T.eq(asked, 1, "idle fade on: the line is looked at")
    DUI:Set("Chat", "hides", "fights")
    stub.RunTimers()
    for _ = 1, 3 do stub.FireEvent("CHAT_MSG_SAY", "hi") end
    stub.FireEvent("CHAT_MSG_LOOT", "loot")
    T.eq(asked, 1, "idle fade off: lines not looked at")
    ChatFrame1:Show()
    stub.Advance(60)
    stub.combat = true   -- switched on mid-fight: the refresh waits, the clock doesn't
    DUI:Set("Chat", "hides", "fightsIdle")
    settle()
    T.eq(ChatFrame1:GetAlpha(), 1, "switched on: shown for the idle time first")
    stub.Advance(DUI:Get("Chat", "idleAfter") + 1)
    settle()
    T.eq(ChatFrame1:GetAlpha(), 0, "then faded")
    stub.combat = false
    stub.RunTimers()
    Chat.Shows = shows
end)

T.test("chat: shortening a line makes no closures or patterns of its own", function()
    login()
    local Tags = stub.chatModule.Tags
    _G.CHAT_SAY_GET = "%s says: "
    local line = "|Hplayer:Bob|h[Bob]|h waves"   -- nothing to shorten, so no new text either
    Tags.Shorten(line, "CHAT_MSG_SAY")
    -- LuaJIT's compiler allocates too, at moments that vary run to run (up to
    -- 44 KB in a parallel run). With it paused, only the addon's own garbage counts.
    if jit then jit.off() end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 500 do Tags.Shorten(line, "CHAT_MSG_SAY") end
    local made = collectgarbage("count") - before
    collectgarbage("restart")
    if jit then jit.on() end
    _G.CHAT_SAY_GET = nil
    T.truthy(made < 4, "500 lines: " .. string.format("%.1f", made) .. " KB of garbage")
end)

T.test("chat: a burst of lines in one frame dresses the bubbles once", function()
    login()
    local Bubbles = stub.chatModule.Bubbles
    local dressed = 0
    local dressAll = Bubbles.DressAll
    Bubbles.DressAll = function(...) dressed = dressed + 1; return dressAll(...) end
    stub.SetBubbles({})
    for _ = 1, 5 do stub.FireEvent("CHAT_MSG_SAY", "hi") end
    stub.FireEvent("CHAT_MSG_YELL", "HI")
    stub.RunTimers()
    T.eq(dressed, 1, "one look the frame after")
    stub.Advance(0.02)
    stub.FireEvent("CHAT_MSG_SAY", "again")
    stub.RunTimers()
    T.eq(dressed, 2, "a line in a later frame looks again")
    Bubbles.DressAll = dressAll
end)

-- Runs the shared tween driver (floating, the grip) and the fade engine.
local function settleFloat()
    local Chat, F = stub.chatModule.Chat, DaylightUI.Fade
    Chat.UpdateFade()
    local M = DaylightUI.Motion
    for _ = 1, 60 do
        if M.Driver() then stub.RunOnUpdate(M.Driver(), 1 / 30) end
    end
    F.Step()
    for _ = 1, 120 do stub.RunOnUpdate(F.driver, 1 / 60) end
end

T.test("chat: dragging the corner grip sizes the chat and keeps it as Width and Height", function()
    login()
    local Chat = stub.chatModule.Chat
    local holder, grip = DaylightUIChat, DaylightUIChatGrip
    T.truthy(grip, "a corner grip")
    T.eq(grip:GetAlpha(), 0, "unseen until the mouse is over the chat")
    function holder:IsMouseOver() return true end
    settleFloat()
    T.eq(grip:GetAlpha(), 1, "seen with the mouse over the chat")
    grip:GetScript("OnMouseDown")(grip)
    T.truthy(Chat.sizing)
    local inset = Chat.inset
    holder:SetSize(600 + 2 * inset, 300 + 2 * inset)   -- the drag
    grip:GetScript("OnMouseUp")(grip)
    stub.RunTimers()
    T.falsy(Chat.sizing)
    T.eq(DaylightUI:Get("Chat", "matchInfo"), false, "no longer the info panel's size")
    T.eq(DaylightUI:Get("Chat", "width"), 600)
    T.eq(DaylightUI:Get("Chat", "height"), 300)
    T.eq(holder:GetWidth(), 600 + 2 * inset, "laid out at the new size")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: floating leaves only the lines; the mouse brings the panel back, typing doesn't", function()
    login()
    local Chat = stub.chatModule.Chat
    local holder = DaylightUIChat
    local over = false
    function holder:IsMouseOver() return over end
    settleFloat()
    T.eq(DaylightUIChatPanel:GetAlpha(), 1, "the panel at rest")
    DaylightUI:Set("Chat", "hides", "always")
    stub.RunTimers()
    stub.Advance(Chat.AWAKE + 1)
    settleFloat()
    T.eq(DaylightUIChatPanel:GetAlpha(), 0, "floating: no panel")
    T.eq(GeneralDockManager:GetAlpha(), 0, "no tab row")
    T.eq(ChatFrame1:GetAlpha(), 1, "the lines stay")
    over = true
    settleFloat()
    T.eq(DaylightUIChatPanel:GetAlpha(), 1, "the mouse over it: the panel back")
    T.eq(GeneralDockManager:GetAlpha(), 1, "and the tabs")
    over = false
    stub.Advance(Chat.AWAKE + 1)
    settleFloat()
    T.eq(DaylightUIChatPanel:GetAlpha(), 0, "a moment after it leaves: floating again")
    function ChatFrame1EditBox:HasFocus() return true end
    Chat.Step(0)
    settleFloat()
    T.eq(DaylightUIChatPanel:GetAlpha(), 0, "typing: still no panel")
    T.eq(GeneralDockManager:GetAlpha(), 0, "nor tabs")
    T.eq(ChatFrame1.shouldFadeAfterInactivity, true, "nor old lines brought back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: a fight floats it at once (Chat hides in fights), its end brings it back", function()
    login()
    local Chat = stub.chatModule.Chat
    function DaylightUIChat:IsMouseOver() return false end
    settleFloat()
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    stub.combat = true
    T.eq(DaylightUIChatPanel:GetAlpha(), 0, "at once, no easing in a fight")
    stub.combat = false
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    settleFloat()
    T.eq(DaylightUIChatPanel:GetAlpha(), 1, "the fight over: back")
    DaylightUI:Set("Chat", "hides", "never")
    stub.RunTimers()
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    settleFloat()
    T.eq(DaylightUIChatPanel:GetAlpha(), 1, "switched off: a fight leaves it")
    T.falsy(Chat.FloatWanted())
end)

T.test("chat: sitting by a campfire with Float the chat floats it; waking brings it back, a fight at once", function()
    login()
    local Chat = stub.chatModule.Chat
    function DaylightUIChat:IsMouseOver() return false end
    settleFloat()
    T.eq(DaylightUIChatPanel:GetAlpha(), 1, "the panel at rest")
    DaylightUI.Fire("Campfire", true)
    T.truthy(Chat.FloatWanted(), "the campfire asks for it")
    T.truthy(DaylightUIChatPanel:GetAlpha() > 0.5, "eases away, not a blink")
    settleFloat()
    T.eq(DaylightUIChatPanel:GetAlpha(), 0, "floating: no panel")
    T.eq(GeneralDockManager:GetAlpha(), 0, "no tab row")
    T.eq(ChatFrame1:GetAlpha(), 1, "the lines stay")
    T.truthy(ChatFrame1:GetFading(), "each line fades on its own")
    DaylightUI.Fire("Campfire", false)
    settleFloat()
    T.eq(DaylightUIChatPanel:GetAlpha(), 1, "you got up: the panel back")
    DaylightUI.Fire("Campfire", true)
    settleFloat()
    DaylightUI.Fire("Campfire", false, true)
    T.eq(DaylightUIChatPanel:GetAlpha(), 1, "woken by a fight: back at once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: floating, a new line fades in; at rest, in a fight or with motion off it shows at once", function()
    login()
    local Chat = stub.chatModule.Chat
    function DaylightUIChat:IsMouseOver() return false end
    local cf = ChatFrame1
    local function arrive()
        cf:AddMessage("hello")
        cf:FakeRefresh()
        return cf.visibleLines[1]
    end
    local line = arrive()
    T.eq(line:GetAlpha(), 1, "not floating: the game's own way")
    DaylightUI:Set("Chat", "hides", "always")
    stub.RunTimers()
    line = arrive()
    T.eq(line:GetAlpha(), 0, "floating: it starts clear, in the same frame")
    stub.Advance(DaylightUI.Motion.NORMAL / 2)
    Chat.Step(0)
    local mid = line:GetAlpha()
    T.truthy(mid > 0 and mid < 1, "half way: easing in (" .. mid .. ")")
    cf:SetAlpha(1); cf:FakeRefresh()   -- the game redraws it at 1 meanwhile
    T.eq(line:GetAlpha(), mid, "a redraw keeps it where it was")
    stub.Advance(DaylightUI.Motion.NORMAL)
    Chat.Step(0)
    T.eq(line:GetAlpha(), 1, "then fully in")
    stub.combat = true
    line = arrive()
    T.eq(line:GetAlpha(), 1, "in a fight: at once")
    stub.combat = false
    DaylightUI:Set("general", "motion", false)
    stub.RunTimers()
    line = arrive()
    T.eq(line:GetAlpha(), 1, "motion off: at once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: whispers in their own tab (the game's whisperMode), or only the main tab", function()
    login()
    T.eq(stub.cvars.whisperMode, "popout_and_inline", "a tab per person by default")
    DaylightUI:Set("Chat", "whisperTabs", false)
    stub.RunTimers()
    T.eq(stub.cvars.whisperMode, "inline")
end)

T.test("chat: message colors are the game's, read and changed through it", function()
    local changed
    login(function()
        _G.ChatTypeInfo = { SKILL = { r = 0.33, g = 0.33, b = 1 } }
        _G.ChangeChatColor = function(t, r, g, b) changed = { t, r, g, b } end
    end)
    local Chat = stub.chatModule.Chat
    T.eq(Chat.ColorOf("SKILL")[3], 1, "read from ChatTypeInfo")
    T.eq(Chat.ColorOf("NOPE")[1], 1, "an unknown kind: white")
    local item
    for _, it in ipairs(stub.chatModule.MESSAGE_COLORS) do
        if it.label == "Skill-up color" then item = it end
    end
    T.truthy(item, "a Skill-up color row")
    T.eq(item.get()[1], 0.33)
    item.set({ 1, 0.5, 0 })
    T.eq(changed[1], "SKILL")
    T.eq(changed[3], 0.5, "through the game's ChangeChatColor")
    _G.ChatTypeInfo, _G.ChangeChatColor = nil, nil
end)

T.test("chat: whisper tabs' words cut short in the tab, cut off with the dock's scroll frame", function()
    login(function()
        GeneralDockManager.scrollFrame = CreateFrame("ScrollFrame", nil, GeneralDockManager)
    end)
    local Chat = stub.chatModule.Chat
    ChatFrame1.isStaticDocked = true
    ChatFrame1Tab:Show(); ChatFrame2Tab:Show()
    ChatFrame2Tab.Text:SetText("Falfan Duskwind")
    Chat.Pass()
    local a, b = Chat.Label(ChatFrame1Tab), Chat.Label(ChatFrame2Tab)
    T.truthy(b:GetParent().__clips, "a whisper tab's label rides a clipping frame")
    T.falsy(a:GetParent().__clips, "a static tab's stays on the row")
    T.eq(b.text:GetNumPoints(), 2, "the words held inside the tab, both sides")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: every tab's words on one line, though the game sets its scrolling tabs higher", function()
    login()
    local Chat = stub.chatModule.Chat
    ChatFrame1Tab:Show(); ChatFrame2Tab:Show()
    Chat.Pass()
    local a, b = Chat.Label(ChatFrame1Tab), Chat.Label(ChatFrame2Tab)
    -- The game puts General on the dock's bottom and a scrolling tab 2.5 px up.
    a:GetParent().GetBottom = function() return 100 end
    ChatFrame1Tab.GetBottom = function() return 100 end
    ChatFrame2Tab.GetBottom = function() return 102.5 end
    Chat.Pass()
    local _, rel, _, x, y = b:GetPoint(1)
    T.eq(rel, ChatFrame2Tab, "still follows its tab sideways")
    T.eq(x, 0)
    T.eq(y, -2.5, "stands on the row's bottom")
    T.eq(select(5, b:GetPoint(2)), -2.5)
    T.eq(select(5, a:GetPoint(1)) or 0, 0, "a tab already on the row stays put")
    local moves, real = 0, b.SetPoint
    b.SetPoint = function(...) moves = moves + 1; return real(...) end
    Chat.Pass()
    T.eq(moves, 0, "placed again only when the game moves it")
    b.SetPoint = real
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: our tabs over the game's: its words see-through, ours picked with the selected tab, no clicks", function()
    login()
    local Chat = stub.chatModule.Chat
    ChatFrame1Tab:Show(); ChatFrame2Tab:Show()
    ChatFrame1Tab.Text:SetText("General"); ChatFrame2Tab.Text:SetText("Trade")
    Chat.Pass()
    local a, b = Chat.Label(ChatFrame1Tab), Chat.Label(ChatFrame2Tab)
    T.truthy(a and b, "one of ours per docked tab")
    T.eq(a.text:GetText(), "General", "the same words")
    T.eq(ChatFrame1Tab.Text:GetAlpha(), 0, "the game's words see-through")
    T.falsy(a:IsMouseEnabled(), "clicks go to the game's tab")
    T.truthy(b.picked, "the selected tab (ChatFrame2) picked")
    T.falsy(a.picked)
    _G.FCFDock_GetSelectedWindow = function() return ChatFrame1 end
    Chat.Pass()
    T.truthy(a.picked, "follows the game's selection")
    T.falsy(b.picked)
    ChatFrame3Tab:Show()
    Chat.Pass()
    T.isnil(Chat.Label(ChatFrame3Tab), "a window out of the dock keeps the game's tab")
    -- The watcher runs 4 times a second, so the same words aren't written again.
    local writes, real = 0, a.text.SetText
    a.text.SetText = function(...) writes = writes + 1; return real(...) end
    Chat.Pass(); Chat.Pass()
    T.eq(writes, 0, "unchanged words: not written")
    ChatFrame1Tab.Text:SetText("Guild")
    Chat.Pass()
    T.eq(writes, 1, "new words: written once")
    T.eq(a.text:GetText(), "Guild")
    a.text.SetText = real
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: the game's time stamp goes tan; the rest of the line is untouched", function()
    login()
    local Tags = stub.chatModule.Tags
    local out = Tags.Shorten("05:32 Bob yells: hi", "CHAT_MSG_MONSTER_YELL")
    T.truthy(out and out:find("^|cff%x%x%x%x%x%x05:32|r Bob yells: hi$"), tostring(out))
    out = Tags.Shorten("03:27 PM Ann: yo", nil)
    T.truthy(out and out:find("03:27 PM|r Ann: yo", 1, true), tostring(out))
    T.isnil(Tags.Shorten("Moonwell: no time here", nil), "no stamp: left alone")
end)

T.test("chat: channel numbers kept with short tags when asked", function()
    login()
    local Tags = stub.chatModule.Tags
    local line = "|Hchannel:channel:1|h[1. General - Elwynn Forest]|h Ann: hi"
    T.truthy(Tags.Shorten(line, "CHAT_MSG_CHANNEL"):find("|h[G]|h", 1, true), "off: the tag alone")
    DaylightUI:Set("Chat", "channelNumbers", true)
    T.truthy(Tags.Shorten(line, "CHAT_MSG_CHANNEL"):find("|h[1. G]|h", 1, true), "on: number and tag")
    local custom = "|Hchannel:channel:5|h[5. MyChannel]|h Ann: hi"
    T.truthy(Tags.Shorten(custom, "CHAT_MSG_CHANNEL"):find("|h[5]|h", 1, true), "an unknown channel: its number, as before")
    DaylightUI:Set("Chat", "channelNumbers", false)
end)

T.test("chat: a channel can have its own short tag, and an empty one goes back", function()
    login()
    local Tags = stub.chatModule.Tags
    local list = _G.GetChannelList
    _G.GetChannelList = function() return 1, "General", false, 7, "Community:123:1", false end
    local general = "|Hchannel:channel:1|h[1. General - Elwynn Forest]|h Ann: hi"
    local heroes = "|Hchannel:channel:5|h[5. Heroes]|h Ann: hi"
    Tags.SetOwn("general", " [Gen|n] ")
    Tags.SetOwn("ch:heroes", "HE")
    T.eq(Tags.Own("general"), "Genn", "brackets, bars and spaces can't get into a line")
    T.truthy(Tags.Shorten(general, "CHAT_MSG_CHANNEL"):find("|h[Genn]|h", 1, true), "a world channel takes it")
    T.truthy(Tags.Shorten(heroes, "CHAT_MSG_CHANNEL"):find("|h[HE]|h", 1, true), "a channel of your own takes it")
    DaylightUI:Set("Chat", "channelNumbers", true)
    T.truthy(Tags.Shorten(heroes, "CHAT_MSG_CHANNEL"):find("|h[5. HE]|h", 1, true), "the number stays when asked")
    DaylightUI:Set("Chat", "channelNumbers", false)
    -- A community reads one name in the list and another on its lines; its number says which.
    Tags.SetOwn("ch:community:123:1", "CO")
    local community = "|Hchannel:channel:7|h[7. Our Friends]|h Ann: hi"
    T.truthy(Tags.Shorten(community, "CHAT_MSG_CHANNEL"):find("|h[CO]|h", 1, true), "found by its number")
    Tags.SetOwn("general", "")
    Tags.SetOwn("ch:heroes", "")
    Tags.SetOwn("ch:community:123:1", "")
    T.isnil(Tags.Own("general"), "empty: nothing kept")
    T.truthy(Tags.Shorten(general, "CHAT_MSG_CHANNEL"):find("|h[G]|h", 1, true), "empty: the standard tag again")
    T.truthy(Tags.Shorten(heroes, "CHAT_MSG_CHANNEL"):find("|h[5]|h", 1, true), "empty: its number again")
    _G.GetChannelList = list
end)

-- ---------------------------------------------------------------------
-- Motion (Feel.lua)
-- ---------------------------------------------------------------------

local function runMotion(seconds)
    local M = DaylightUI.Motion
    for _ = 1, math.floor((seconds or 1) * 30) do
        if M.Driver() then stub.RunOnUpdate(M.Driver(), 1 / 30) end
    end
end

local function at(f, left, right, bottom)
    f.GetLeft = function() return left end
    f.GetRight = function() return right end
    f.GetBottom = function() return bottom end
end

local function feel() return stub.chatModule.Feel.Parts() end

T.test("chat: the line under the picked tab glides to the next one picked", function()
    login()
    local Chat = stub.chatModule.Chat
    Chat.Pass()
    local a, b = Chat.Label(ChatFrame1Tab), Chat.Label(ChatFrame2Tab)
    T.eq(b.line:GetAlpha(), 0, "each tab's own line stays unseen: one line for the row")
    local glider = feel().glider
    T.truthy(glider:IsShown(), "the row's line shows")
    T.eq(select(2, glider:GetPoint(1)), b, "under the picked tab")
    local row = b:GetParent()
    at(row, 0, 400, 100)
    at(b, 60, 120, 100)
    at(a, 0, 50, 100)
    _G.FCFDock_GetSelectedWindow = function() return ChatFrame1 end
    Chat.Pass()
    runMotion(0.05)
    local _, rel, _, x = glider:GetPoint(1)
    T.eq(rel, row, "on its way, placed along the row")
    T.truthy(x > 0 and x < 60, "between the two tabs: " .. tostring(x))
    runMotion(1)
    T.eq(select(2, glider:GetPoint(1)), a, "at rest under the new tab, following it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: an unread tab breathes (a whisper tab in the whisper color); the game's flash art is cleared", function()
    local alerting = {}
    login(function()
        ChatFrame1Tab.glow = ChatFrame1Tab:CreateTexture()
        ChatFrame1Tab.glow:SetTexture("glow art")
    end)
    _G.ChatFrameUtil.IsTabAlerting = function(tab) return alerting[tab] == true end
    _G.ChatTypeInfo = { WHISPER = { r = 1, g = 0.5, b = 1 } }
    local Chat, Style = stub.chatModule.Chat, DaylightUI.Style
    T.eq(ChatFrame1Tab.glow.__texture, nil, "the game's flash art cleared")
    Chat.Pass()
    local a = Chat.Label(ChatFrame1Tab)
    local lo = Style.INK.LABEL
    T.eq(select(1, a.text:GetTextColor()), lo[1], "at rest: tan")
    alerting[ChatFrame1Tab] = true
    ChatFrame1.chatType = "WHISPER"
    Chat.Pass()
    Chat.Step(stub.chatModule.Feel.BREATH / 2)   -- half a breath gives the full color
    local r, g = a.text:GetTextColor()
    T.truthy(math.abs(r - 1) < 0.01 and math.abs(g - 0.5) < 0.01, "breathes into the whisper color: " .. r .. " " .. g)
    alerting[ChatFrame1Tab] = nil
    Chat.Pass()
    T.eq(select(1, a.text:GetTextColor()), lo[1], "looked at: tan again")
    alerting[ChatFrame2Tab] = true
    Chat.Pass()
    T.isnil(Chat.Label(ChatFrame2Tab).alert, "the tab you're on never breathes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: the input box's outline eases into the channel's color", function()
    login()
    _G.ChatTypeInfo = { SAY = { r = 1, g = 1, b = 1 }, PARTY = { r = 0.6, g = 0.6, b = 1 },
        CHANNEL2 = { r = 1, g = 0.8, b = 0.6 } }
    local Chat, Style = stub.chatModule.Chat, DaylightUI.Style
    local eb = ChatFrame1EditBox
    function eb:HasFocus() return true end
    eb:SetAttribute("chatType", "PARTY")
    Chat.Step(1)
    local shell
    for _, k in ipairs({ eb:GetChildren() }) do shell = shell or Style.GetShell(k) end
    runMotion(1)
    T.eq(shell.opts.borderColor[1], 0.6, "party blue")
    T.eq(shell.opts.borderColor[3], 1)
    eb:SetAttribute("chatType", "CHANNEL")
    eb:SetAttribute("channelTarget", 2)
    Chat.Step(1)
    runMotion(1)
    T.eq(shell.opts.borderColor[2], 0.8, "a channel's own color, by its number")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: the typing box eases in out of a fight and snaps in one", function()
    login()
    local Chat = stub.chatModule.Chat
    local eb = ChatFrame1EditBox
    local focused = false
    function eb:HasFocus() return focused end
    Chat.Step(1)
    focused = true
    Chat.Step(DaylightUI.Motion.FAST / 2)
    T.truthy(eb:GetAlpha() > 0 and eb:GetAlpha() < 1, "on its way in: " .. eb:GetAlpha())
    T.truthy(eb:IsMouseEnabled(), "typing at once")
    focused = false
    Chat.Step(1)
    Chat.fight = true
    focused = true
    Chat.Step(0.01)
    T.eq(eb:GetAlpha(), 1, "in a fight: at once")
    Chat.fight = nil
end)

-- A whisper in a dungeon fight caused hundreds of errors. The game's box took the
-- sender's secret name as its tell target, and from then on its HasFocus answered
-- a secret boolean, which addon code can't truth-test. The game's own record of
-- the box being typed in (ChatFrameUtil's active window, set on focus gained and
-- cleared on focus lost) stays plain.
T.test("chat: a box whose focus reads secret (a whisper's hidden name) asks the game's active box", function()
    login()
    local Chat = stub.chatModule.Chat
    local eb = ChatFrame1EditBox
    local active
    _G.ChatFrameUtil.GetActiveWindow = function() return active end
    function eb:HasFocus() return stub.Secret(active == self) end
    Chat.Step(1)
    T.eq(eb:GetAlpha(), 0, "not typing: the box stays hidden")
    T.falsy(eb:IsMouseEnabled(), "and lets clicks through")
    T.falsy(Chat.Typing(), "nobody typing")
    active = eb
    Chat.Step(1)
    T.eq(eb:GetAlpha(), 1, "typing: the box shows")
    T.truthy(Chat.Typing(), "typing")
    active = nil
    Chat.Step(1)
    T.eq(eb:GetAlpha(), 0, "done: hidden again")
    _G.ChatFrameUtil.GetActiveWindow = nil
end)

T.test("chat: a whisper runs one light round the panel, then it eases away", function()
    login()
    local light = feel().light
    light.GetWidth = function() return 300 end    -- the fake game doesn't size by anchors
    light.GetHeight = function() return 100 end
    stub.FireEvent("CHAT_MSG_WHISPER", "hi", "Someone")
    runMotion(0.2)
    local lit = 0
    for _, t in ipairs({ light:GetRegions() }) do if t:IsShown() then lit = lit + 1 end end
    T.truthy(light:GetAlpha() > 0, "the light shows")
    T.truthy(lit > 0, "the border traced")
    runMotion(2)
    T.eq(light:GetAlpha(), 0, "gone again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: scrolled up, a pill eases in with the game's jump button under it for the click", function()
    login()
    local Chat = stub.chatModule.Chat
    local pill = feel().pill
    local bottom = true
    function ChatFrame2:AtBottom() return bottom end
    local btn = ChatFrame2.ScrollToBottomButton
    Chat.Pass()
    T.falsy(btn:IsMouseEnabled(), "at the newest line: the game's button takes no clicks")
    T.falsy(pill:IsShown())
    bottom = false
    Chat.Pass()
    T.eq(select(2, btn:GetPoint(1)), pill, "the game's button lies under our pill")
    T.truthy(pill:IsShown(), "the pill shows")
    T.truthy(btn:IsMouseEnabled(), "and the click is the game's")
    T.eq(pill.text:GetText(), "Newest")
    stub.FireEvent("CHAT_MSG_SAY", "hi")
    Chat.Pass()
    T.eq(pill.text:GetText(), "New messages", "a line while scrolled up")
    bottom = true
    Chat.Pass()
    runMotion(1)
    T.falsy(pill:IsShown(), "back at the newest: it eases away")
    T.falsy(btn:IsMouseEnabled())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: a level-up or your own epic sends a light along the tab line; others' loot doesn't", function()
    login()
    local Feel = stub.chatModule.Feel
    local quality = 4
    _G.C_Item = _G.C_Item or {}
    local was = C_Item.GetItemInfo
    C_Item.GetItemInfo = function() return "Sword", "link", quality end
    local me = UnitGUID("player")
    local msg = "You receive loot: |cffa335ee|Hitem:123::|h[Sword]|h|r."
    T.truthy(Feel.EpicLoot(msg, "Me", "", "", "Me", "", 0, 0, "", 0, 1, me), "your epic")
    T.falsy(Feel.EpicLoot(msg, "Ann", "", "", "Ann", "", 0, 0, "", 0, 1, "Player-1-ANN"), "someone else's")
    quality = 3
    T.falsy(Feel.EpicLoot(msg, "Me", "", "", "Me", "", 0, 0, "", 0, 1, me), "a blue")
    C_Item.GetItemInfo = was
    stub.FireEvent("PLAYER_LEVEL_UP", 10)
    runMotion(0.2)
    T.truthy(feel().shine:IsShown(), "the light runs")
    runMotion(2)
    T.falsy(feel().shine:IsShown(), "and goes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: the panel's border lights while the grip sizes it, and eases back", function()
    login()
    local s = DaylightUI.Style.GetShell(DaylightUIChatPanel)
    DaylightUIChatGrip:GetScript("OnMouseDown")(DaylightUIChatGrip)
    runMotion(1)
    T.truthy(s.opts.borderColor, "lit while sizing")
    DaylightUIChatGrip:GetScript("OnMouseUp")(DaylightUIChatGrip)
    stub.RunTimers()
    runMotion(1)
    T.isnil(s.opts.borderColor, "its own border again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- The Daylight chat box (Box.lua)
-- ---------------------------------------------------------------------

local function daylight(before)
    login(function()
        _G.ChatTypeInfo = { SYSTEM = { id = 1, r = 1, g = 1, b = 0 }, LOOT = { id = 2, r = 0, g = 0.7, b = 0 },
                            GUILD = { id = 3, r = 0.2, g = 1, b = 0.2 }, SAY = { id = 4, r = 1, g = 1, b = 1 } }
        if before then before() end
    end, "daylight")
    return stub.chatModule.Box, DaylightUIChatBox
end

-- The game's AddMessage on a window for a player's line: its id, the event and the
-- event's arguments (the 11th is the line's id), as in ChatFrameOverrides.
local function said(cf, text, event, lineId, id)
    local args = { text, "Bob", n = 14 }
    args[11] = lineId
    cf:AddMessage(text, 1, 1, 1, id or 3, nil, nil, event, args)
end

local function boxTexts(box)
    local out = {}
    for i = 1, box:GetNumMessages() do out[i] = (box:GetMessageInfo(i)) end
    return out
end

T.test("chat daylight: every window's line lands in the box once; the game's chat out of sight", function()
    local Box, box = daylight()
    T.truthy(box and box:IsShown(), "the box shown")
    T.eq(ChatFrame1:GetAlpha(), 0, "the game's window out of sight")
    T.falsy(ChatFrame1:IsMouseEnabled(), "and taking no clicks")
    T.eq(ChatFrame1Tab:GetAlpha(), 0, "its tab too")
    T.eq(GeneralDockManager:GetAlpha(), 0, "and the dock")
    T.truthy(ChatFrame1EditBox:IsIgnoringParentAlpha(), "the typing box keeps its own alpha")
    -- The same line reaching two windows is kept once, by its line id.
    said(ChatFrame1, "|Hchannel:GUILD|h[Guild]|h Bob: hi", "CHAT_MSG_GUILD", 7)
    said(ChatFrame3, "|Hchannel:GUILD|h[Guild]|h Bob: hi", "CHAT_MSG_GUILD", 7)
    -- The game's own line (no event, only its type id) is kept once too.
    ChatFrame1:AddMessage("You receive loot: [Linen]", 0, 0.7, 0, 2)
    ChatFrame3:AddMessage("You receive loot: [Linen]", 0, 0.7, 0, 2)
    local texts = boxTexts(box)
    T.eq(#texts, 2, "two lines")
    T.eq(texts[1], GUILD_SHORT, "short tags on our copy")
    T.eq(ChatFrame1.lines[#ChatFrame1.lines - 1][1], GUILD, "the window's own line untouched")
    T.eq(Box.Log()[1][5], "guild", "its kind")
    T.eq(Box.Log()[2][5], "loot")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: lines whose event carries line id 0 (system, loot) are each kept", function()
    local _, box = daylight()
    said(ChatFrame1, "You receive loot: [Linen]", "CHAT_MSG_LOOT", 0, 2)
    said(ChatFrame1, "You receive loot: [Wool]", "CHAT_MSG_LOOT", 0, 2)
    said(ChatFrame1, "You are now Away", "CHAT_MSG_SYSTEM", 0, 1)
    T.eq(#boxTexts(box), 3, "none taken for the one before")
    said(ChatFrame3, "You are now Away", "CHAT_MSG_SYSTEM", 0, 1)
    T.eq(#boxTexts(box), 3, "the same line in another window: still once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: the same line twice in one window is two lines", function()
    local _, box = daylight()
    ChatFrame1:AddMessage("Repaired for 1g", 1, 1, 0, 1)
    ChatFrame3:AddMessage("Repaired for 1g", 1, 1, 0, 1)
    ChatFrame1:AddMessage("Repaired for 1g", 1, 1, 0, 1)
    ChatFrame3:AddMessage("Repaired for 1g", 1, 1, 0, 1)
    T.eq(#boxTexts(box), 2, "each window's copy once, both lines kept")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a secret line without an id is taken from the main window only", function()
    local _, box = daylight()
    local s = stub.Secret("a locked line")
    ChatFrame3:AddMessage(s, 1, 1, 1, 1)
    T.eq(box:GetNumMessages(), 0, "not from another window")
    ChatFrame1:AddMessage(s, 1, 1, 1, 1)
    T.eq(box:GetNumMessages(), 1, "from the main one")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: each tab shows its kinds; another tab with something new breathes; picking refills", function()
    local Box, box = daylight()
    said(ChatFrame1, "guild line", "CHAT_MSG_GUILD", 1)
    said(ChatFrame1, "say line", "CHAT_MSG_SAY", 2, 4)
    T.eq(#boxTexts(box), 2, "General shows everything")
    local guildTab = Box.Labels()
    local buttons = {}
    for b in pairs(guildTab) do buttons[#buttons + 1] = b end
    T.eq(#buttons, 4, "General, Guild, Trade, Loot")
    T.truthy(next(guildTab), "tabs")
    Box.Pick(2)
    T.eq(table.concat(boxTexts(box), "|"), "guild line", "the Guild tab: guild only")
    ChatFrame1:AddMessage("You receive loot: [Linen]", 0, 0.7, 0, 2)
    T.eq(#boxTexts(box), 1, "loot not in the Guild tab")
    local lootTab
    for b in pairs(Box.Labels()) do if b.words == (_G.LOOT or "Loot") then lootTab = b end end
    T.truthy(lootTab and lootTab.alert, "the Loot tab breathes")
    Box.Pick(4)
    T.isnil(lootTab.alert, "looked at: it stops")
    T.eq(table.concat(boxTexts(box), "|"), "You receive loot: [Linen]")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a loot line finds its tab by its event, whatever type number it brings", function()
    local Box, box = daylight()
    local Kinds = stub.chatModule.Kinds
    local text = "You receive loot: [Linen]"
    T.falsy(Kinds.Filter(ChatFrame1, "CHAT_MSG_LOOT", text), "the filter keeps the line")
    ChatFrame1:AddMessage(text, 0, 0.7, 0, 999)   -- no event, a number that can't be named
    ChatFrame1:AddMessage("a system line", 1, 1, 0, 1)
    Box.Pick(4)
    T.eq(table.concat(boxTexts(box), "|"), text, "in the Loot tab; the next line isn't taken for loot")
    T.isnil(Kinds.Heard(ChatFrame1), "used once")
end)

T.test("chat daylight: more tabs than fit slide on a clipped rail, never over the header's icons", function()
    local Box = daylight()
    local CH = stub.chatModule
    for _ = 1, 6 do CH.Tabs.Add(false) end
    Box.LayoutTabs()
    local rail = Box.TabButton(1):GetParent()
    local strip = rail:GetParent()
    T.truthy(strip:DoesClipChildren(), "cut off at the strip's end")
    function strip:GetWidth() return 120 end
    Box.LayoutTabs()
    local room = Box.main.railWidth - 120
    T.truthy(room > 0, "more than fit")
    T.truthy(strip:IsMouseEnabled(), "it takes the mouse now")
    strip:GetScript("OnMouseWheel")(strip, -1)
    runMotion(1)
    T.eq(Box.main.scroll, math.min(room, Box.WHEEL), "the wheel slides them")
    strip:GetScript("OnMouseWheel")(strip, 99)
    runMotion(1)
    T.eq(Box.main.scroll, 0, "never past the first")
    local realCursor, x = _G.GetCursorPosition, 500
    _G.GetCursorPosition = function() return x, 0 end
    Box.PanStart()
    x = 480
    Box.PanMove()
    T.eq(Box.main.scroll, 20, "the row dragged follows the mouse")
    T.truthy(Box.PanStop(), "let go")
    _G.GetCursorPosition = realCursor
    Box.Pick(#Box.Tabs())
    runMotion(1)
    local last = Box.TabButton(#Box.Tabs())
    T.truthy(last.x + last:GetWidth() <= Box.main.scroll + 120, "a tab picked slides into view")
    Box.Pick(1)
    runMotion(1)
    T.eq(Box.main.scroll, 0, "and back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: floating, the mouse eases every line back, never a jump to full", function()
    local Box, box = daylight()
    local CH = stub.chatModule
    DaylightUI:Set("Chat", "hides", "always")
    local over = false
    function DaylightUIChat:IsMouseOver() return over end
    CH.Chat.UpdateFade()
    box:AddMessage("an old line", 1, 1, 1)
    stub.Advance(5)
    box:FakeRefresh()
    local line = box.visibleLines[1]
    line:SetAlpha(0.1)
    over = true
    CH.Chat.UpdateFade()
    box:FakeRefresh()   -- the game's redraw: every line at full, in one frame
    T.truthy(line:GetAlpha() < 0.2, "still where it was the frame the game drew it full: got " .. line:GetAlpha())
    stub.Advance(DaylightUI.Motion.SLOW / 2)
    CH.Feel.Step(0.01)
    local half = line:GetAlpha()
    T.truthy(half > 0.2 and half < 1, "on its way: got " .. half)
    stub.Advance(DaylightUI.Motion.SLOW)
    CH.Feel.Step(0.01)
    T.eq(line:GetAlpha(), 1, "there")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a link click is the game's own, for the main window", function()
    local _, box = daylight()
    local got
    _G.SetItemRef = function(link, text, button, frame) got = { link, text, button, frame } end
    box:GetScript("OnHyperlinkClick")(box, "player:Bob", "[Bob]", "LeftButton")
    T.eq(got and got[1], "player:Bob")
    T.eq(got[4], DEFAULT_CHAT_FRAME, "as if clicked in the main window")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's click on a community invite (ItemRefHandlersShared.lua, CommunitiesHyperlink.lua).
-- From an addon's click it makes the ticket listener untrusted and the answer is refused.
T.test("chat daylight: a community invite never runs the game's click from the box", function()
    local _, box = daylight()
    local says, reached, inserted = {}, {}, {}
    local print, ref, modified, insert = DaylightUI.Print, _G.SetItemRef, _G.IsModifiedClick, _G.ChatFrameUtil.InsertLink
    DaylightUI.Print = function(text) says[#says + 1] = text end
    _G.SetItemRef = function(link)
        reached[#reached + 1] = link
        if string.find(link, "^clubTicket") then
            error("ADDON_ACTION_BLOCKED: GetLastTicketResponse from a listener made under taint")
        end
    end
    local click = function(link, text, button)
        box:GetScript("OnHyperlinkClick")(box, link, text, button or "LeftButton")
    end
    click("clubTicket:ABC123", "[Join: Friends]")
    T.eq(#reached, 0, "the game's click stays out of it")
    T.eq(#says, 1, "the player is told where it opens")

    -- Shift-click with the box open pastes it, as the game's own click would.
    _G.IsModifiedClick = function(k) return k == "CHATLINK" end
    _G.ChatFrameUtil.InsertLink = function(text) inserted[#inserted + 1] = text; return true end
    click("clubTicket:ABC123", "[Join: Friends]")
    T.deq(inserted, { "[Join: Friends]" })
    T.eq(#says, 1, "nothing to say then")

    -- With no box open, the game's click would go on to the listener.
    _G.ChatFrameUtil.InsertLink = function() return false end
    click("clubTicket:ABC123", "[Join: Friends]")
    T.eq(#reached, 0)
    T.eq(#says, 2)

    _G.IsModifiedClick = modified
    click("item:19019", "[Thunderfury]")
    T.deq(reached, { "item:19019" }, "other links stay the game's")
    DaylightUI.Print, _G.SetItemRef, _G.ChatFrameUtil.InsertLink = print, ref, insert
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's parked windows lie under the box and still catch link clicks with
-- their mouse off. Right-clicking a name hit the long [2. Trade - City] under it
-- and opened the channel menu.
T.test("chat daylight: a parked game window's links are off, and back with the classic style", function()
    daylight(function() ChatFrame1:SetHyperlinksEnabled(true) end)
    T.eq(ChatFrame1:GetHyperlinksEnabled(), false, "nothing under the box takes a click")
    DaylightUI:Set("Chat", "style", "classic")
    stub.RunTimers()
    T.eq(ChatFrame1:GetHyperlinksEnabled(), true, "the game's window works again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Questie rewrites quest links in chat into its own |Hquestie: links. The game's
-- SetItemRef, Shift-clicked, pastes a link it doesn't know as is (GetFixedLink,
-- HandleModifiedItemClick), and that never reaches anyone as a link. Questie's own
-- fix only hooks the game's chat windows, so the Daylight box needs its own.
local QUESTIE_ID = "questie:98403:Player-4618-0193E5BF"
local QUESTIE_TEXT = "|H" .. QUESTIE_ID .. "|h|cFFFF1A1A[|r|cFFFF1A1A[12+] Twisted Hatred|r|cFFFF1A1A]|r|h"

local function shiftClickWorld(native)
    local _, box = daylight()
    local world = { inserted = {} }
    _G.IsModifiedClick = function(k) return k == "CHATLINK" end
    _G.GetQuestLink = function() return native end
    _G.ChatFrameUtil.InsertLink = function(text) world.inserted[#world.inserted + 1] = text; return true end
    _G.SetItemRef = function(_, text) _G.ChatFrameUtil.InsertLink(text) end
    world.click = function(link, text, button)
        box:GetScript("OnHyperlinkClick")(box, link, text, button or "LeftButton")
    end
    return world
end

local function shiftClickDone()
    _G.IsModifiedClick, _G.GetQuestLink = nil, nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end

T.test("chat daylight: Shift-click a Questie quest link: the game's real link goes in", function()
    local native = "|cffff2020|Hquest:98403:0|h[Twisted Hatred]|h|r"
    local w = shiftClickWorld(native)
    w.click(QUESTIE_ID, QUESTIE_TEXT)
    T.deq(w.inserted, { native })
    shiftClickDone()
end)

T.test("chat daylight: a Questie link for a quest not in your log goes in Questie's words", function()
    local w = shiftClickWorld(nil)
    w.click(QUESTIE_ID, QUESTIE_TEXT)
    T.deq(w.inserted, { "[Twisted Hatred (98403)]" })
    shiftClickDone()
end)

T.test("chat daylight: other links and other clicks stay the game's own", function()
    local w = shiftClickWorld("|cffff2020|Hquest:98403:0|h[Twisted Hatred]|h|r")
    local native = "|cffffff00|Hquest:168:0|h[Collecting Memories]|h|r"
    w.click("quest:168:0", native)
    T.deq(w.inserted, { native }, "a plain quest link is the game's")
    w.inserted = {}
    w.click(QUESTIE_ID, QUESTIE_TEXT, "RightButton")
    T.deq(w.inserted, { QUESTIE_TEXT }, "only a left click links")
    w.inserted = {}
    _G.IsModifiedClick = function() return false end
    w.click(QUESTIE_ID, QUESTIE_TEXT)
    T.deq(w.inserted, { QUESTIE_TEXT }, "no Shift: the game's, Questie's tooltip")
    shiftClickDone()
end)

T.test("chat daylight: Classic and back at once; lines heard meanwhile are kept", function()
    local Box, box = daylight()
    DaylightUI:Set("Chat", "style", "classic")
    stub.RunTimers()
    T.falsy(box:IsShown(), "the box away")
    T.eq(ChatFrame1:GetAlpha(), 1, "the game's window back")
    T.truthy(ChatFrame1:IsMouseEnabled(), "taking clicks again")
    said(ChatFrame1, "while classic", "CHAT_MSG_GUILD", 9)
    DaylightUI:Set("Chat", "style", "daylight")
    stub.RunTimers()
    T.truthy(box:IsShown())
    T.eq(boxTexts(box)[1], "while classic", "the line heard in Classic shows")
    T.eq(ChatFrame1:GetAlpha(), 0, "the game's window out of sight again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: history saved from the box with each line's kind, back after a reload", function()
    local Box, box = daylight()
    said(ChatFrame1, "guild line", "CHAT_MSG_GUILD", 1)
    stub.FireEvent("PLAYER_LOGOUT")
    local saved = DaylightUI.DB.Character().chatHistory
    T.truthy(saved and saved.box, "the box's lines saved")
    T.eq(saved.box[1][5], "guild", "with its kind")
    Box.Log()[1] = nil
    box:Clear()
    T.eq(stub.chatModule.History.Restore(stub.chatModule.Chat and DaylightUI:GetModule("Chat").db), 1)
    local texts = boxTexts(box)
    T.eq(texts[1], "guild line", "back in the box")
    T.truthy(string.find(texts[2], "before reload", 1, true), "under the divider")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: scrolled up, the pill shows; its click goes to the newest line", function()
    local _, box = daylight()
    for i = 1, 10 do said(ChatFrame1, "line " .. i, "CHAT_MSG_GUILD", i) end
    box:ScrollUp()
    stub.chatModule.Chat.Pass()
    runMotion(1)
    local pill = feel().pill
    T.truthy(pill:IsShown(), "the pill")
    T.truthy(pill:IsMouseEnabled(), "taking the click itself")
    pill:GetScript("OnClick")(pill)
    T.truthy(box:AtBottom(), "at the newest line")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: scrolled up, the scroll bar stays and says how far; back at the newest it leaves", function()
    local _, box = daylight()
    local Feel, Chat = stub.chatModule.Feel, stub.chatModule.Chat
    for i = 1, 30 do said(ChatFrame1, "line " .. i, "CHAT_MSG_GUILD", i) end
    Chat.Pass()
    local bar = Feel.Bar(box)
    T.falsy(bar and bar:IsShown(), "at the newest line it's away: nothing runs each frame")

    box:ScrollUp()
    bar = Feel.Bar(box)
    T.truthy(bar:IsShown(), "the wheel brings it at once, without waiting for the watcher")
    T.eq(bar.max, box:GetMaxScrollRange())
    stub.Advance(30)
    Chat.Pass()
    T.truthy(bar:IsShown(), "it stays as long as you're scrolled up")
    T.truthy(bar.lit, "in the accent, so it's seen at a glance")

    bar.To(0)
    T.truthy(box:AtTop(), "the top of the bar is the oldest line")
    bar.To(bar.max)
    T.truthy(box:AtBottom(), "the bottom of the bar is the newest line")
    T.falsy(bar.lit, "back to the usual pale thumb")

    Chat.Pass()
    T.truthy(bar:IsShown(), "it fades before it goes")
    stub.Advance(5)
    Chat.Pass()
    T.falsy(bar:IsShown(), "back at the newest: gone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: /dui chat classic and /dui chat daylight switch at once", function()
    local Box, box = daylight()
    Box.Command("classic")
    stub.RunTimers()
    T.eq(DaylightUI:Get("Chat", "style"), "classic")
    T.falsy(box:IsShown())
    Box.Command("daylight")
    stub.RunTimers()
    T.truthy(box:IsShown())
    Box.Command("")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- The Daylight chat box's extras and tab editor
-- ---------------------------------------------------------------------

local function channelLine(cf, text, sender, lineId, base)
    local args = { text, sender, n = 14 }
    args[9], args[11] = base or "Trade", lineId
    cf:AddMessage(text, 1, 0.75, 0.75, 5, nil, nil, "CHAT_MSG_CHANNEL", args)
end

T.test("chat daylight: spam in public channels hidden (repeats, adverts) under one note; guild never", function()
    local _, box = daylight()
    channelLine(ChatFrame1, "WTS Bloodfang Hood 40g", "Brann", 1)
    channelLine(ChatFrame1, "WTS Bloodfang Hood 40g", "Brann", 2)
    local texts = boxTexts(box)
    T.eq(#texts, 2, "the line and a note")
    T.truthy(string.find(texts[2], "1 spam line hidden", 1, true), "the note counts it")
    channelLine(ChatFrame1, "cheap gold, fast delivery www.gold.example", "Spammer", 3)
    stub.Advance(stub.chatModule.Box.NOTE_GAP + 0.1)
    stub.RunTimers()
    texts = boxTexts(box)
    T.eq(#texts, 2, "still one note")
    T.truthy(string.find(texts[2], "2 spam lines hidden", 1, true), "now two")
    said(ChatFrame1, "cheap gold lol", "CHAT_MSG_GUILD", 4)
    T.eq(#boxTexts(box), 3, "guild never filtered")
    box:GetScript("OnHyperlinkClick")(box, "daylightchat:spam:all", "show", "LeftButton")
    texts = boxTexts(box)
    T.eq(#texts, 4, "show: the two come in, the note goes")
    for _, t in ipairs(texts) do T.falsy(string.find(t, "spam lines hidden", 1, true), "no note left") end
    DaylightUI:Set("Chat", "spamRepeats", false)
    stub.RunTimers()
    channelLine(ChatFrame1, "WTS Bloodfang Hood 40g", "Brann", 5)
    T.eq(#boxTexts(box), 5, "repeats shown when that's off")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: your own words and phrases hide public lines, by what was typed", function()
    local _, box = daylight()
    local Extras = stub.chatModule.Extras
    T.truthy(Extras.SpamAdd("  Boost   Run "), "a phrase goes in, its spaces tidied")
    T.truthy(Extras.SpamAdd("gold"), "a word")
    T.truthy(Extras.SpamAdd("$$$"), "a word of symbols")
    T.truthy(Extras.SpamAdd("trade"), "a word that's also the channel's name")
    T.falsy(Extras.SpamAdd("GOLD"), "already there, whatever the capitals")
    T.falsy(Extras.SpamAdd("   "), "nothing to add")
    T.eq(table.concat(Extras.SpamList(), "|"), "Boost Run|gold|$$$|trade")
    stub.RunTimers()
    local n = 0
    -- The event's message and the line as shown differ here (channelLine sends one text as both).
    local function line(body, sender)
        n = n + 1
        local before = stub.chatModule.Box.spam
        local args = { body, sender or "Brann", n = 14 }
        args[9], args[11] = "Trade", n
        ChatFrame1:AddMessage("[2. Trade] [" .. (sender or "Brann") .. "]: " .. body, 1, 1, 1, 5, nil, nil, "CHAT_MSG_CHANNEL", args)
        return stub.chatModule.Box.spam == before + 1
    end
    T.truthy(line("selling a BOOST   RUN tonight"), "a phrase, any capitals and spacing")
    T.truthy(line("got gold?"), "a word")
    T.truthy(line("win $$$ now"), "symbols")
    T.falsy(line("Golden Lotus 5g each"), "whole words only")
    T.falsy(line("LF healer for Scarlet", "Gold"), "never the sender's name")
    T.falsy(line("WTS Bloodfang Hood 40g"), "never the channel's name in front of the line")
    T.truthy(line("open to trade offers"), "the word in the message itself still counts")
    said(ChatFrame1, "gold for the guild bank", "CHAT_MSG_GUILD", 900)
    T.truthy(string.find(table.concat(boxTexts(box), "\n"), "guild bank", 1, true), "guild never")
    Extras.SpamRemove("gold")
    stub.RunTimers()
    T.falsy(line("got more gold?"), "removed: shown again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: your name lights up, its tab glows, the soft sound when switched on", function()
    local played = {}
    local Box, box = daylight(function()
        _G.PlaySoundFile = function(f) if string.find(f, "whisper-", 1, true) then played[#played + 1] = f end end
    end)
    DaylightUI:Set("Chat", "alertSound", true)
    local me = UnitName("player")
    Box.Pick(3)   -- Trade
    said(ChatFrame1, "is " .. me .. " coming?", "CHAT_MSG_GUILD", 1)
    local guildTab
    for b in pairs(Box.Labels()) do if b.words == (_G.GUILD or "Guild") then guildTab = b end end
    T.truthy(guildTab.alert, "the Guild tab glows")
    local general
    for b in pairs(Box.Labels()) do if b.words == (_G.GENERAL or "General") then general = b end end
    T.truthy(general.alert, "an everything tab too, for an alert")
    Box.Pick(2)
    local text = boxTexts(box)[1]
    T.truthy(string.find(text, "|cff", 1, true) and string.find(text, me, 1, true), "the name painted")
    T.eq(#played, 1, "one soft sound: " .. table.concat(played, ","))
    said(ChatFrame1, "hello " .. me, "CHAT_MSG_GUILD", 2)
    T.eq(#played, 1, "not again right away")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a mention's glow fades with its line (the game fades lines with no redraw)", function()
    local _, box = daylight()
    local Chat = stub.chatModule.Chat
    said(ChatFrame1, "is " .. UnitName("player") .. " coming?", "CHAT_MSG_GUILD", 1)
    stub.Advance(5)   -- past the new line's ease in
    box:FakeRefresh()
    local glow
    for _, r in ipairs({ box:GetRegions() }) do
        if r.__texture == "Interface\\Buttons\\WHITE8X8" then glow = r end
    end
    T.truthy(glow and glow:IsShown(), "the glow behind the line")
    local line = box.visibleLines[1]
    -- The game's UpdateFading sets each line's alpha, then hides it at 0, with no
    -- callback. The glow used to stay at full after its line faded even though its
    -- SetAlpha followed the line: a gradient's own colors carry its alpha, so the
    -- fade goes in those, and it's hidden once gone.
    local full = glow.__gradient[2].a
    T.truthy(full > 0, "lit at the left end")
    line:SetAlpha(0.5)
    Chat.Step(0)
    T.near(glow.__gradient[2].a, full * 0.5, 1e-6, "fades with its line")
    T.eq(glow.__gradient[3].a, 0, "still clear at the right end")
    line:SetAlpha(0)
    line:Hide()
    Chat.Step(0)
    T.falsy(glow:IsShown(), "gone with its line")
    -- The mouse brings the line back through a redraw.
    box:FakeRefresh()
    Chat.Step(0)
    T.truthy(glow:IsShown(), "back with its line")
    T.near(glow.__gradient[2].a, full, 1e-6, "at full again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: group lines get role icons and no whisper or invite links", function()
    local invited
    local _, box = daylight(function()
        _G.C_PartyInfo = _G.C_PartyInfo or {}
        _G.C_PartyInfo.InviteUnit = function(n) invited = n end
        -- The game's own (TextureUtil in Blizzard_SharedXMLBase): an inline atlas.
        _G.CreateAtlasMarkup = function(atlas, w, h) return ("|A:%s:%d:%d|a"):format(atlas, h or 0, w or 0) end
    end)
    channelLine(ChatFrame1, "LF2M SFM need tank and healer", "Torvik", 1, "LookingForGroup")
    local text = boxTexts(box)[1]
    T.isnil(string.find(text, "daylightchat:", 1, true), "no links of ours on the line")
    local _, icons = string.gsub(text, "|A:", "")
    T.eq(icons, 2, "one role icon each for tank and healer (never one inside another's name)")
    T.truthy(string.find(text, "|cff%x%x%x%x%x%xtank|r"), "tank in its color")
    T.truthy(string.find(text, "|cff%x%x%x%x%x%xhealer|r"), "healer in its color")
    -- A line saved before they went can still hold one.
    box:GetScript("OnHyperlinkClick")(box, "daylightchat:i:Torvik", "[invite]", "LeftButton")
    T.isnil(invited, "an old saved link does nothing")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: tabs edited: what one shows, renamed, added, moved, removed", function()
    local Box, box = daylight()
    local Tabs = stub.chatModule.Tabs
    said(ChatFrame1, "hi all", "CHAT_MSG_SAY", 1, 4)
    Tabs.SetKind(2, "say", true)
    stub.RunTimers()
    Box.Pick(2)
    T.eq(table.concat(boxTexts(box), "|"), "hi all", "the Guild tab now shows say too")
    Tabs.Rename(2, "Social")
    stub.RunTimers()
    T.eq(Box.Tabs()[2].name, "Social")
    local n = Tabs.Add(false)
    stub.RunTimers()
    T.eq(n, 5)
    T.eq(#Box.Tabs(), 5)
    Tabs.Move(5, -1)
    stub.RunTimers()
    T.eq(Box.Tabs()[4].name, "New tab", "moved left")
    Tabs.Remove(4)
    stub.RunTimers()
    T.eq(#Box.Tabs(), 4)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: say, guild, party and the rest can have their own short tags", function()
    login()
    local Tags = stub.chatModule.Tags
    local guild = "|Hchannel:GUILD|h[Guild]|h Ann: hi"
    local party = "|Hchannel:PARTY|h[Party]|h Ann: hi"
    local name = "|Hplayer:Ann|h[Ann]|h"
    local says = name .. " says: hi"
    local tells = "To " .. name .. ": hi"
    local fmt = { say = _G.CHAT_SAY_GET, inform = _G.CHAT_WHISPER_INFORM_GET }
    _G.CHAT_SAY_GET = "%s says: "
    _G.CHAT_WHISPER_INFORM_GET = "To %s: "
    Tags.SetOwn("guild", "GLD")
    Tags.SetOwn("party", "Grp")
    Tags.SetOwn("say", "Sy")
    Tags.SetOwn("whisper", "Wh")
    T.truthy(Tags.Shorten(guild, "CHAT_MSG_GUILD"):find("|h[GLD]|h", 1, true), "guild takes it")
    T.truthy(Tags.Shorten(party, "CHAT_MSG_PARTY"):find("|h[Grp]|h", 1, true), "party takes it")
    T.truthy(Tags.Shorten(party, "CHAT_MSG_PARTY_LEADER"):find("|h[GrpL]|h", 1, true), "the leader still reads apart")
    T.truthy(Tags.Shorten(says, "CHAT_MSG_SAY"):find("[Sy] ", 1, true), "speech takes it")
    T.truthy(Tags.Shorten(tells, "CHAT_MSG_WHISPER_INFORM"):find("[To] ", 1, true), "what you send stays [To]")
    Tags.SetOwn("guild", "")
    Tags.SetOwn("party", "")
    Tags.SetOwn("say", "")
    Tags.SetOwn("whisper", "")
    T.truthy(Tags.Shorten(party, "CHAT_MSG_PARTY_LEADER"):find("|h[PL]|h", 1, true), "empty: the standard tag again")
    T.truthy(Tags.Shorten(says, "CHAT_MSG_SAY"):find("[S] ", 1, true), "empty: the standard tag again")
    _G.CHAT_SAY_GET, _G.CHAT_WHISPER_INFORM_GET = fmt.say, fmt.inform
end)

T.test("chat daylight: a tab's Show window renames it from the box up top", function()
    local Box = daylight()
    local Tabs, Filter = stub.chatModule.Tabs, stub.chatModule.Filter
    local saved = Box.Tabs()[2].name
    Tabs.ShowMenu(UIParent, 2)
    local f = Filter.Frame()
    local box = f.nameBox
    T.eq(box:GetText(), saved, "the box shows the tab's name")
    local focused = false
    box.HasFocus = function() return focused end    -- the fake game's boxes never hold focus
    local function typed(text)
        focused = true
        box:SetText(text)
        box:GetScript("OnTextChanged")(box, true)
    end
    typed("Raid chat ")
    T.eq(Box.Tabs()[2].name, "Raid chat", "typing renames it, no spaces at the end")
    T.eq(f.title:GetText(), "Show in Raid chat", "the title follows")
    T.eq(box:GetText(), "Raid chat ", "the box leaves your typing alone")
    typed("")
    T.eq(Box.Tabs()[2].name, "Raid chat", "an empty box never leaves a tab with no name")
    focused = false
    box:GetScript("OnEditFocusLost")(box)
    T.eq(box:GetText(), "Raid chat", "leaving the box empty brings the name back")
    box:SetText("Not typed")
    box:GetScript("OnTextChanged")(box, false)
    T.eq(Box.Tabs()[2].name, "Raid chat", "only typing renames")
    Tabs.ShowMenu(UIParent, 1)
    T.eq(box:GetText(), Box.Tabs()[1].name, "another tab: its name")
    box.HasFocus = nil
    Filter.Close()
    Tabs.Rename(2, saved)
end)

T.test("chat daylight: a tab moved or removed with its Show window open stays that tab's", function()
    local Box = daylight()
    local Tabs, Filter = stub.chatModule.Tabs, stub.chatModule.Filter
    local second = Box.Tabs()[2].name
    Tabs.ShowMenu(UIParent, 2)
    Tabs.MoveTo(2, 1)
    T.eq(Filter.Tab(), 1, "the window follows its tab")
    T.eq(Filter.Frame().nameBox:GetText(), second, "so typing renames the right one")
    Tabs.MoveTo(1, 2)
    T.eq(Filter.Tab(), 2)
    local n = Tabs.Add()
    Filter.Open(n)
    Tabs.Remove(n)
    T.falsy(DaylightUI.Win.IsOpen(Filter.Frame()), "its tab removed: the window closes")
end)

T.test("chat daylight: a tab's Show has a tag box on each channel, not on Other channels", function()
    daylight()
    local Tabs, Filter, Tags = stub.chatModule.Tabs, stub.chatModule.Filter, stub.chatModule.Tags
    local list = _G.GetChannelList
    _G.GetChannelList = function() return 1, "General", false, 5, "Heroes", false end
    Tabs.ShowMenu(UIParent, 2)
    local rows = {}
    for _, b in ipairs(Filter.Rows()) do
        if b.tag and b:IsShown() then rows[b.kind] = b end
    end
    T.truthy(rows["general"] and rows["ch:heroes"], "a box beside each channel")
    T.eq(rows["general"].tag.hint:GetText(), "G", "the box shows the standard tag until you type")
    T.eq(rows["ch:heroes"].tag.hint:GetText(), "5", "a channel with no standard tag shows its number")
    T.truthy(rows["general"].tag:IsShown())
    T.falsy(rows["channel"].tag:IsShown(), "Other channels are many channels: no one tag")
    T.eq(rows["guild"].tag.hint:GetText(), "G", "a kind of chat has one too")
    T.truthy(rows["guild"].tag:IsShown())
    local emote
    for _, b in ipairs(Filter.Rows()) do
        if b.kind == "emote" then emote = b end
    end
    T.falsy(emote.tag:IsShown(), "emotes have no tag to change")
    local box = rows["ch:heroes"].tag
    box:SetText("HE")
    box:GetScript("OnTextChanged")(box, true)
    T.eq(Tags.Own("ch:heroes"), "HE", "typing sets it")
    box:SetText("")
    box:GetScript("OnTextChanged")(box, false)
    T.eq(Tags.Own("ch:heroes"), "HE", "only typing does")
    Tabs.ShowMenu(UIParent, 2)
    T.eq(box:GetText(), "HE", "opened again it shows your tag")
    Filter.Close()
    DaylightUI:Set("Chat", "shortTags", false)
    Tabs.ShowMenu(UIParent, 2)
    T.falsy(box:IsShown(), "no short tags: no tag boxes")
    DaylightUI:Set("Chat", "shortTags", true)
    Tags.SetOwn("ch:heroes", "")
    Filter.Close()
    _G.GetChannelList = list
end)

T.test("chat daylight: a tab's Show lists the channels you're in, each its own switch", function()
    local Box, box = daylight()
    local Tabs, Filter, Kinds = stub.chatModule.Tabs, stub.chatModule.Filter, stub.chatModule.Kinds
    local joined = { 1, "General", false, 2, "Trade", false, 5, "Heroes", false }
    local list = _G.GetChannelList
    _G.GetChannelList = function() return unpack(joined) end
    local function words()
        local out = {}
        for _, b in ipairs(Filter.Rows()) do
            if b:IsShown() then out[b.text:GetText()] = b.kind end
        end
        return out
    end
    Tabs.ShowMenu(UIParent, 2)
    local rows = words()
    T.eq(rows["Heroes"], "ch:heroes", "your own channel has a switch, by its name")
    T.eq(rows["General"], "general", "a channel you're in reads as the game names it")
    T.truthy(rows["Looking for group"], "the world channels you're not in stay")
    T.truthy(rows["Other channels"], "and the one for everything else")
    T.eq(Filter.TypeOf("ch:heroes"), "CHANNEL5", "colored as the game colors it")

    Filter.Flip("ch:heroes")
    stub.RunTimers()
    T.truthy(Kinds.Shows(Box.Tabs()[2], "ch:heroes"), "it's on the tab")
    T.falsy(Kinds.Shows(Box.Tabs()[2], "ch:others"), "no other channel came along")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_CHANNEL", { [9] = "Heroes" })), "ch:heroes", "its lines are that kind")

    -- A community reads one name in the list (its switch) and another on its
    -- lines. The line's channel number says which switch it belongs to.
    joined = { 1, "General", false, 7, "Community:123:1", false }
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_CHANNEL", { [8] = 7, [9] = "Our Friends" })), "ch:community:123:1",
        "a community's lines go by its switch")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_CHANNEL", { [8] = 1, [9] = "General - Elwynn Forest" })), "general")
    -- Other people's community lines come by an event of their own, a channel line
    -- to the game (ChatFrameOverrides.lua: type == "COMMUNITIES_CHANNEL" or
    -- "CHANNEL...", with the same number and name). Without this, a tab with only
    -- the community on showed just the player's own lines.
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_COMMUNITIES_CHANNEL", { [8] = 7, [9] = "Community:123:1" })), "ch:community:123:1",
        "a community's own event is its channel's line too")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_COMMUNITIES_CHANNEL", { [8] = 7, [9] = "Our Friends" })), "ch:community:123:1")

    -- Leaving it, the open window follows.
    joined = { 1, "General", false, 2, "Trade", false }
    stub.FireEvent("CHANNEL_UI_UPDATE")
    T.falsy(words()["Heroes"], "gone from the list")

    -- "Other channels" still means every channel without a switch of its own.
    Filter.Open(3)
    T.falsy(Kinds.Shows(Box.Tabs()[3], "ch:others"))
    Filter.Flip("channel")
    stub.RunTimers()
    T.truthy(Kinds.Shows(Box.Tabs()[3], "ch:others"), "other channels covers it")
    joined = { 5, "Heroes", false }
    Filter.Open(3)
    Filter.Flip("ch:heroes")
    stub.RunTimers()
    T.falsy(Kinds.Shows(Box.Tabs()[3], "ch:heroes"), "one flipped off stays off")
    T.truthy(Kinds.Shows(Box.Tabs()[3], "ch:others"), "the rest stay")

    -- From Everything, one channel off keeps the rest.
    Filter.Open(1)
    Filter.Flip("ch:heroes")
    stub.RunTimers()
    T.falsy(Kinds.Shows(Box.Tabs()[1], "ch:heroes"))
    T.truthy(Kinds.Shows(Box.Tabs()[1], "ch:others"))
    T.truthy(stub.chatModule.Extras.Public("ch:others"), "spam rules cover your channels too")
    Filter.Close()
    _G.GetChannelList = list
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a tab's Show opens a window of switches; many kinds at once, each in its color", function()
    local Box = daylight()
    local Tabs, Filter = stub.chatModule.Tabs, stub.chatModule.Filter
    Tabs.ShowMenu(UIParent, 2)
    local f = Filter.Frame()
    T.truthy(f and DaylightUI.Win.IsOpen(f), "the window is open")
    T.eq(Filter.Tab(), 2)
    Filter.Flip("say")
    Filter.Flip("trade")
    stub.RunTimers()
    local tab = Box.Tabs()[2]
    T.truthy(tab.kinds.guild and tab.kinds.officer and tab.kinds.say and tab.kinds.trade,
        "the kinds it had stay, the new ones join them")
    Filter.Flip("say")
    stub.RunTimers()
    T.falsy(Box.Tabs()[2].kinds.say, "flipped off again")
    -- From Everything, one kind off keeps the rest.
    Filter.Open(1)
    Filter.Flip("loot")
    stub.RunTimers()
    tab = Box.Tabs()[1]
    T.falsy(tab.all, "no longer everything")
    T.falsy(tab.kinds.loot, "loot off")
    T.truthy(tab.kinds.say and tab.kinds.system and tab.kinds.guild, "every other kind still on")
    local c = Filter.ColorOf("guild")
    local g = ChatTypeInfo.GUILD
    T.truthy(g == nil or (c[1] == g.r and c[2] == g.g), "the name wears the guild color")
    local picked
    local set = _G.ChangeChatColor
    _G.ChangeChatColor = function(t, r, g, b) picked = { t, r, g, b } end
    Filter.SetColor("guild", { 0.2, 0.4, 0.6 })
    Filter.SetColor("say", { 1, 0, 0 })
    _G.ChangeChatColor = set
    T.eq(picked and picked[1], "SAY", "a swatch sets the kind's main chat type")
    T.eq(picked and picked[2], 1)
    Tabs.Remove(1)
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    Filter.Close()
end)

T.test("chat daylight: say, yell and emotes are kinds of their own; a tab saved before keeps showing all three", function()
    local Box, box = daylight()
    local Kinds = stub.chatModule.Kinds
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_YELL")), "yell")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_TEXT_EMOTE")), "emote")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_INSTANCE_CHAT")), "instance")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_COMBAT_FACTION_CHANGE")), "reputation")
    DaylightUI:Set("Chat", "tabs", { { name = "Old", kinds = { say = true, progress = true } } })
    stub.RunTimers()
    local tab = Box.Tabs()[1]
    T.truthy(tab.kinds.say and tab.kinds.yell and tab.kinds.emote, "say brought yell and emote along")
    T.truthy(tab.kinds.reputation and tab.kinds.skill and tab.kinds.achievement, "progress brought its kinds along")
    T.falsy(tab.kinds.money, "nothing it didn't show")
    T.eq(tab.v, Kinds.VERSION, "upgraded once")
    stub.chatModule.Tabs.SetKind(1, "yell", false)
    stub.RunTimers()
    T.falsy(Box.Tabs()[1].kinds.yell, "yell off stays off")
    T.truthy(Box.Tabs()[1].kinds.emote)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a tab remembers the channel you last talked in, whispers aside", function()
    local Box = daylight()
    local CH = stub.chatModule
    local Tabs = CH.Tabs
    for _, t in ipairs({ "GUILD", "SAY", "CHANNEL", "WHISPER" }) do
        ChatTypeInfo[t] = ChatTypeInfo[t] or { r = 1, g = 1, b = 1 }
        ChatTypeInfo[t].sticky = 1
    end
    ChatTypeInfo.YELL = { r = 1, g = 0, b = 0, sticky = 0 }
    local joined = { 1, "General", false, 2, "Trade", false }
    local list, name = _G.GetChannelList, _G.GetChannelName
    _G.GetChannelList = function() return unpack(joined) end
    _G.GetChannelName = function(id) return id end
    local eb = ChatFrame1EditBox
    local function talk(chatType, text, target)
        eb:SetAttribute("chatType", chatType)
        if target then eb:SetAttribute("channelTarget", target) end
        send(eb, text or "hello")
        stub.RunTimers()
    end
    local function click(i)
        local b = Box.TabButton(i)
        b:GetScript("OnClick")(b, "LeftButton")
        stub.RunTimers()
    end
    local function boxOn() return eb:GetAttribute("chatType"), eb:GetAttribute("stickyType") end

    Box.Pick(2)
    talk("GUILD")
    T.eq(Box.Tabs()[2].talk.type, "GUILD", "the Guild tab heard /g")
    Box.Pick(3)
    talk("CHANNEL", "wts", 2)
    T.eq(Box.Tabs()[3].talk.kind, "trade", "a channel by what it is: its number differs per character")
    T.falsy(Box.Tabs()[1].talk, "another tab learned nothing")

    click(2)
    local now, sticky = boxOn()
    T.eq(now, "GUILD", "back on the Guild tab, the box is on guild")
    T.eq(sticky, "GUILD", "and stays there after each line")
    click(3)
    T.eq((boxOn()), "CHANNEL", "the Trade tab's channel")
    T.eq(eb:GetAttribute("channelTarget"), 2)

    click(2)
    joined = { 1, "General", false, 3, "Trade", false }
    click(3)
    T.eq(eb:GetAttribute("channelTarget"), 3, "the channel moved: its new number")
    click(2)
    joined = { 1, "General", false }
    click(3)
    T.eq((boxOn()), "GUILD", "a channel you left: the box stays as it is")
    joined = { 1, "General", false, 2, "Trade", false }

    -- What doesn't count: whispers, a one-off yell, a command, an empty box.
    click(2)
    talk("WHISPER")
    T.eq(Box.Tabs()[2].talk.type, "GUILD", "a whisper is never remembered")
    talk("YELL")
    T.eq(Box.Tabs()[2].talk.type, "GUILD", "a yell doesn't stick, as in the game")
    talk("SAY", "/nosuchcommand")
    T.eq(Box.Tabs()[2].talk.type, "GUILD", "a slash command isn't talking")
    talk("SAY", "")
    T.eq(Box.Tabs()[2].talk.type, "GUILD", "nor is an empty box")

    -- Typing in a box on its way out never changes where the words go.
    eb:SetAttribute("chatType", "WHISPER")
    eb:SetAttribute("stickyType", "WHISPER")
    eb:Show()
    function eb:HasFocus() return true end
    click(3)
    T.eq((boxOn()), "WHISPER", "while typing the box is left alone")
    function eb:HasFocus() return false end

    -- The box belongs to the corner panel. A tab on the second panel or the
    -- combat log's never sets it, and another box never teaches a tab.
    local tabs = Box.Tabs()
    tabs[4].side, tabs[4].talk = true, { type = "GUILD" }
    DaylightUI:Set("Chat", "tabs", tabs)
    stub.RunTimers()
    eb:SetAttribute("chatType", "SAY")
    Tabs.TalkHere(4)
    T.eq((boxOn()), "SAY", "a second panel's tab leaves the box alone")
    local other = { GetAttribute = function() return "SAY" end, GetText = function() return "hi" end }
    Tabs.Heard(other)
    stub.RunTimers()
    T.eq(Box.Tabs()[2].talk.type, "GUILD", "a whisper window's own box teaches nothing")

    -- A reload starts on the first tab, and its channel comes back too.
    Box.Pick(2)
    eb:SetAttribute("chatType", "SAY")
    DaylightUI:Set("Chat", "style", "classic")
    stub.RunTimers()
    T.falsy(Box.On())
    talk("SAY")
    T.eq(Box.Tabs()[2].talk.type, "GUILD", "the Classic style has one box and no tabs of ours")
    eb:SetAttribute("chatType", "SAY")
    DaylightUI:Set("Chat", "style", "daylight")
    stub.RunTimers()
    T.eq((boxOn()), "GUILD", "the tab shown when the box comes up")

    _G.GetChannelList, _G.GetChannelName = list, name
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game prints "Changed Channel: [6. LookingForGroup 84]". The number after the
-- name must not make it a channel of its own.
T.test("chat daylight: LookingForGroup with a number after it is still LFG", function()
    daylight()
    local CH = stub.chatModule
    local Kinds, Tags = CH.Kinds, CH.Tags
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_CHANNEL", { [9] = "LookingForGroup 84" })), "lfg", "its lines")
    T.eq(Kinds.OfChannel("LookingForGroup 84"), "lfg", "the channel list's name")
    T.eq(Tags.Standard("LookingForGroup 84", 6), "LFG", "its tag")
    T.eq(Kinds.OfChannel("Trade - City"), "trade", "a zone after it still goes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The names the game really gives them, from a player's chat:
-- [5. Trade (Services) - English], [6. Trade (Local) - Ironforge].
T.test("chat daylight: Trade (Services) and Trade (Local) reach the Trade tab, each with its own switch and tag", function()
    local Box = daylight()
    local CH = stub.chatModule
    local Kinds, Tags, Filter = CH.Kinds, CH.Tags, CH.Filter
    local function kindOf(base) return select(2, Kinds.Of(nil, "CHAT_MSG_CHANNEL", { [9] = base })) end
    local services, tradeLocal = kindOf("Trade (Services) - English"), kindOf("Trade (Local) - Ironforge")
    T.eq(kindOf("Trade - English"), "trade", "the plain one stays Trade")
    T.truthy(services ~= "trade" and tradeLocal ~= "trade" and services ~= tradeLocal, "each its own kind")
    T.eq(kindOf("Services"), services, "the short name is the same channel")
    T.eq(Kinds.OfChannel("Trade (Services)"), services, "the channel list's name matches its lines")

    local trade = Box.Tabs()[3]
    T.truthy(Kinds.Shows(trade, "trade") and Kinds.Shows(trade, services) and Kinds.Shows(trade, tradeLocal),
        "a new Trade tab shows all three")
    T.eq(Tags.Standard("Trade (Services) - English", 5), "TS")
    T.eq(Tags.Standard("Trade (Local) - Ironforge", 6), "TL")
    T.eq(Tags.Shorten("|Hchannel:channel:5|h[5. Trade (Services) - English]|h boost", "CHAT_MSG_CHANNEL"),
        "|Hchannel:channel:5|h[TS]|h boost", "not a bare [5]")
    T.eq(Tags.Shorten("|Hchannel:channel:6|h[6. Trade (Local) - Ironforge]|h WTS", "CHAT_MSG_CHANNEL"),
        "|Hchannel:channel:6|h[TL]|h WTS", "not a bare [6]")
    T.truthy(CH.Extras.Public(services) and CH.Extras.Public(tradeLocal), "the spam rules look here")
    T.truthy(CH.Extras.TALK[services] and CH.Extras.TALK[tradeLocal], "alert words light here, as in Trade")

    -- A channel you're not in still has its switch, so you can pick it ahead.
    local joined = { 1, "General", false, 2, "Trade", false }
    local list = _G.GetChannelList
    _G.GetChannelList = function() return unpack(joined) end
    Filter.Open(3)
    local rows = {}
    for _, item in ipairs(Filter.ChannelList()) do rows[item.kind] = item end
    T.truthy(rows[services] and rows[tradeLocal], "both listed")
    T.eq(rows[services].standard, "TS", "with its standard tag in the box")
    T.eq(rows[tradeLocal].standard, "TL")
    Filter.Flip(services)
    stub.RunTimers()
    T.falsy(Kinds.Shows(Box.Tabs()[3], services), "Services off alone")
    T.truthy(Kinds.Shows(Box.Tabs()[3], tradeLocal), "Local stays")
    T.truthy(Kinds.Shows(Box.Tabs()[3], "trade"), "Trade stays")
    Filter.Close()
    _G.GetChannelList = list

    -- A Trade tab from before gets both. One already flipped off stays off.
    DaylightUI:Set("Chat", "tabs", {
        { name = "Old", kinds = { trade = true }, v = 3 },
        { name = "Choosy", kinds = { trade = true, [services] = false }, v = 3 },
        { name = "Guild", kinds = { guild = true }, v = 3 },
    })
    stub.RunTimers()
    local tabs = Box.Tabs()
    T.truthy(Kinds.Shows(tabs[1], services) and Kinds.Shows(tabs[1], tradeLocal), "an old Trade tab gets both")
    T.falsy(Kinds.Shows(tabs[2], services), "one switched off stays off")
    T.truthy(Kinds.Shows(tabs[2], tradeLocal))
    T.falsy(Kinds.Shows(tabs[3], services), "a tab without Trade gets neither")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The channel list names it "TradeLocal" (as it names Trade (Services) "Services"),
-- so the Show window had a "TradeLocal" row that did nothing and, under it,
-- "Trade (Local)" as if you weren't in it.
T.test("chat daylight: the channel list's TradeLocal is Trade (Local), one row, and what was set on the old row comes along", function()
    local Box = daylight()
    local CH = stub.chatModule
    local Kinds, Tags, Filter = CH.Kinds, CH.Tags, CH.Filter
    local tradeLocal = Kinds.TRADE_LOCAL
    T.eq(Kinds.OfChannel("TradeLocal"), tradeLocal, "the list's name is the lines' channel")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_CHANNEL", { [9] = "Trade (Local) - Ironforge" })), tradeLocal)
    T.eq(Tags.Standard("TradeLocal", 5), "TL", "its tag, not a bare 5")

    local joined = { 1, "General", false, 2, "Trade", false, 4, "Services", false, 5, "TradeLocal", false }
    local list = _G.GetChannelList
    _G.GetChannelList = function() return unpack(joined) end
    Filter.Open(3)
    local count = 0
    for _, item in ipairs(Filter.ChannelList()) do
        if item.kind == tradeLocal then
            count = count + 1
            T.eq(item.standard, "TL")
        end
        T.truthy(item.kind ~= "ch:tradelocal", "no row of its own")
    end
    T.eq(count, 1, "listed once")
    Filter.Close()
    _G.GetChannelList = list

    -- A tab with the old row flipped off wanted Trade (Local) off, and its tag too.
    DaylightUI:Set("Chat", "tabs", {
        { name = "Off", kinds = { trade = true, [tradeLocal] = true, ["ch:tradelocal"] = false }, v = 4 },
        { name = "On", kinds = { trade = true, [tradeLocal] = true, ["ch:tradelocal"] = true }, v = 4 },
    })
    DaylightUI:Set("Chat", "channelTags", { ["ch:tradelocal"] = "Loc" })
    stub.RunTimers()
    local tabs = Box.Tabs()
    T.falsy(Kinds.Shows(tabs[1], tradeLocal), "off on the old row is off")
    T.truthy(Kinds.Shows(tabs[2], tradeLocal), "on stays on")
    T.eq(tabs[1].kinds["ch:tradelocal"], nil, "the old row's switch is gone")
    T.eq(Tags.Own(tradeLocal), "Loc", "the tag typed on the old row")
    DaylightUI:Set("Chat", "channelTags", nil)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: Battle.net whispers have their own switch; a tab with whispers keeps them, only once", function()
    local Box = daylight()
    local CH = stub.chatModule
    local Kinds = CH.Kinds
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_BN_WHISPER")), "bnet")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_BN_WHISPER_INFORM")), "bnet")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_WHISPER")), "whisper")
    DaylightUI:Set("Chat", "tabs", {
        { name = "Old", kinds = { whisper = true }, v = 2 },
        { name = "None", kinds = { party = true }, v = 2 },
    })
    stub.RunTimers()
    T.truthy(Box.Tabs()[1].kinds.bnet, "whispers brought Battle.net whispers along")
    T.falsy(Box.Tabs()[2].kinds.bnet, "nothing it didn't show")
    T.falsy(Box.Tabs()[2].kinds.instance, "an older split isn't run again: instance off stays off")
    CH.Tabs.SetKind(1, "bnet", false)
    stub.RunTimers()
    T.falsy(Box.Tabs()[1].kinds.bnet, "off stays off")
    T.truthy(Box.Tabs()[1].kinds.whisper, "whispers stay")
    CH.Filter.Open(1)
    local row
    for _, b in ipairs(CH.Filter.Rows()) do
        if b.kind == "bnet" then row = b end
    end
    T.truthy(row, "the Show window has its row")
    T.eq(CH.Filter.TypeOf("bnet"), "BN_WHISPER", "in its own color")
    CH.Filter.Close()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a tab dragged along the row moves there; the menu has no Move left/right", function()
    local Box = daylight()
    local Tabs = stub.chatModule.Tabs
    local names = {}
    for i, t in ipairs(Box.Tabs()) do names[i] = t.name end
    local b = Box.TabButton(1)
    stub.cursorPos = { (b.x or 0) + 5, 0 }
    Box.DragStart(1)
    local right = Box.TabButton(4)
    stub.cursorPos = { (right.x or 0) + right:GetWidth() + 5, 0 }
    Box.DragMove()
    Box.DragStop()
    stub.RunTimers()
    local now = Box.Tabs()
    T.eq(now[#now].name, names[1], "the first tab now last")
    T.eq(now[1].name, names[2], "the others closed up")
    T.eq(Tabs.Order(4, 1, 4)[4], 1)
    local W, open = DaylightUI.Widgets, DaylightUI.Widgets.OpenMenu
    local menu
    W.OpenMenu = function(_, keys, values) menu = values end
    Tabs.OpenMenu(UIParent, 2)
    W.OpenMenu = open
    T.falsy(menu.left or menu.right, "no Move left / Move right rows")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a tab's Text size menu sets the size and outline; the slider shows a real size", function()
    local Box, box = daylight()
    local DUI = DaylightUI
    local Tabs = stub.chatModule.Tabs
    T.eq(stub.chatModule.Chat.TextSize(), 14, "untouched: the game's own size, never 0")
    T.eq(select(2, box:GetFont()), 14)
    local W, open = DUI.Widgets, DUI.Widgets.OpenMenu
    local menu
    W.OpenMenu = function(owner, keys, values, current, onPick, width, opts)
        menu = { keys = keys, values = values, onPick = onPick, opts = opts }
    end
    Tabs.OpenMenu(UIParent, 1)
    T.truthy(menu.values.size and menu.values.size:find("14", 1, true),
        "the tab menu shows the text size in use")
    T.truthy(menu.opts.more.size and menu.opts.more.show, "rows that open another menu wear the chevron")
    menu.onPick("size")
    T.truthy(menu.opts.checked(14), "the size in use ticked")
    menu.onPick(18)
    menu.onPick("outline")
    stub.RunTimers()
    W.OpenMenu = open
    T.eq(DUI:Get("Chat", "textSize"), 18)
    T.eq(select(2, box:GetFont()), 18, "the box at the new size")
    T.eq(select(3, box:GetFont()), "OUTLINE")
    T.truthy(menu.opts.checked(18) and menu.opts.checked("outline") and not menu.opts.checked(14), "ticks follow")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a combat log tab shows the game's combat log in the chat's place", function()
    local selected
    local Box, box = daylight(function()
        _G.FCFDock_SelectWindow = function(_, cf) selected = cf end
    end)
    local Tabs = stub.chatModule.Tabs
    local i = Tabs.Add(true)
    stub.RunTimers()
    Box.Pick(i)
    T.eq(selected, ChatFrame2, "the combat log selected in the dock")
    T.eq(ChatFrame2:GetAlpha(), 1, "and seen")
    T.falsy(box:IsShown(), "our list away")
    stub.chatModule.Chat.Pass()
    T.eq(ChatFrame2:GetAlpha(), 1, "the watcher leaves it seen")
    Box.Pick(1)
    T.eq(selected, ChatFrame1, "the main window again")
    T.eq(ChatFrame2:GetAlpha(), 0)
    T.truthy(box:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: the + and the row's empty space offer a new tab or a combat log tab", function()
    local Box = daylight()
    local W, open = DaylightUI.Widgets, DaylightUI.Widgets.OpenMenu
    local menu
    W.OpenMenu = function(owner, keys, values, current, onPick)
        menu = { keys = keys, values = values, onPick = onPick }
    end
    local count = #Box.Tabs()
    Box.main.plus:GetScript("OnClick")(Box.main.plus)
    T.eq(table.concat(menu.keys, " "), "new combat", "the + asks which")
    T.eq(menu.values.combat, "New combat log tab")
    T.eq(#Box.Tabs(), count, "nothing added yet")
    menu.onPick("combat")
    T.eq(#Box.Tabs(), count + 1)
    T.truthy(Box.Tabs()[count + 1].combat, "a combat log tab")
    T.eq(Box.Picked(), count + 1, "and picked")
    menu = nil
    local strip = Box.main.plus:GetParent():GetParent()
    T.truthy(strip:IsMouseEnabled(), "the empty space takes the mouse")
    strip:GetScript("OnMouseUp")(strip, "LeftButton")
    T.falsy(menu, "a left click does nothing")
    strip:GetScript("OnMouseUp")(strip, "RightButton")
    T.truthy(menu, "a right-click opens it")
    W.OpenMenu = open
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- Whispers in the Daylight chat box (Talk, Tiles, Convo, Thread, Hub)
-- ---------------------------------------------------------------------

-- CHAT_MSG_WHISPER's arguments: text, sender ... arg11 line id, arg12 guid.
local function whisper(text, sender, event, guid)
    stub.FireEvent(event or "CHAT_MSG_WHISPER", text, sender, "", "", "", "", 0, 0, "", 0, 1, guid or "Player-1-0001")
end

local function shownTiles()
    local out = {}
    for _, b in ipairs({ DaylightUIChatTiles:GetChildren() }) do
        if b:IsShown() and b.key then out[#out + 1] = b end
    end
    return out
end

T.test("chat whispers: a whisper makes a tile with its unread count and a preview", function()
    daylight(function()
        _G.GetPlayerInfoByGUID = function() return "Mage", "MAGE", "Gnome", "GNOME", 2, "Lephoque", "", 60 end
    end)
    local CH = stub.chatModule
    whisper("got the key?", "Lephoque")
    local c = CH.Talk.Get("w:Lephoque")
    T.truthy(c, "a conversation")
    T.eq(c.class, "MAGE", "its class from the GUID")
    T.eq(c.unread, 1)
    local tiles = shownTiles()
    T.eq(#tiles, 1, "one tile")
    T.eq(tiles[1].count:GetText(), "1", "its unread count")
    runMotion(0.5)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: a tile's right-click menu ignores the player and closes the conversation", function()
    local ignored
    daylight(function()
        _G.C_FriendList = _G.C_FriendList or {}
        _G.C_FriendList.AddIgnore = function(n) ignored = n; return true end
    end)
    local CH = stub.chatModule
    whisper("buy gold cheap", "Spammer")
    local tile = shownTiles()[1]
    local keys, values, onPick
    local open = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, k, v, _, pick) keys, values, onPick = k, v, pick end
    tile:GetScript("OnClick")(tile, "RightButton")
    DaylightUI.Widgets.OpenMenu = open
    T.truthy(values and values.ignore, "Ignore is in the menu")
    T.eq(keys[#keys - 1], "ignore", "just above Forget")
    onPick("ignore")
    T.eq(ignored, "Spammer", "the game's ignore list gets the name")
    T.truthy(CH.Talk.Get("w:Spammer").closed, "the conversation closes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: a tile's click opens the conversation; Enter sends; the reply comes back as yours", function()
    local sent
    daylight(function()
        _G.C_ChatInfo = _G.C_ChatInfo or {}
        _G.C_ChatInfo.SendChatMessage = function(text, kind, _, to) sent = { text, kind, to } end
    end)
    local CH = stub.chatModule
    whisper("got the key?", "Lephoque")
    local tile = shownTiles()[1]
    tile:GetScript("OnClick")(tile, "LeftButton")
    T.truthy(CH.Convo.Showing("w:Lephoque"), "open")
    T.eq(CH.Talk.Get("w:Lephoque").unread, 0, "read")
    local t = CH.Convo.Thread()
    t.input:SetText("omw")
    t.input:GetScript("OnEnterPressed")(t.input)
    T.eq(sent and sent[1], "omw")
    T.eq(sent[2], "WHISPER")
    T.eq(sent[3], "Lephoque")
    whisper("omw", "Lephoque", "CHAT_MSG_WHISPER_INFORM")
    local c = CH.Talk.Get("w:Lephoque")
    T.eq(#c.msgs, 2)
    T.truthy(c.msgs[2].me, "yours")
    T.eq(c.unread, 0, "your own line isn't unread")
    T.truthy(t.rows[2] and t.rows[2]:IsShown(), "drawn")
    tile:GetScript("OnClick")(tile, "LeftButton")
    runMotion(1)
    T.falsy(CH.Convo.Showing("w:Lephoque"), "a second click tucks it away")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: shown in their window only, or the chat only", function()
    local _, box = daylight()
    local CH = stub.chatModule
    DaylightUI:Set("Chat", "whispersIn", "window")
    stub.RunTimers()
    ChatFrame1:AddMessage("[Lephoque] whispers: hi", 1, 0.5, 1, nil, nil, nil, "CHAT_MSG_WHISPER", { "hi", "Lephoque", n = 14 })
    T.eq(box:GetNumMessages(), 0, "not in the chat")
    DaylightUI:Set("Chat", "whispersIn", "chat")
    stub.RunTimers()
    whisper("hi", "Lephoque")
    T.falsy(DaylightUIChatTiles:IsShown(), "no tiles")
    T.truthy(CH.Talk.Get("w:Lephoque"), "still kept for the hub")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

local function markAway(on)
    stub.units.player = stub.units.player or {}
    stub.units.player.afk = on
end

T.test("chat whispers: the away message answers once per person", function()
    local sent = {}
    daylight(function()
        _G.C_ChatInfo = _G.C_ChatInfo or {}
        _G.C_ChatInfo.SendChatMessage = function(text, _, _, to) sent[#sent + 1] = { text, to } end
    end)
    DaylightUI:Set("Chat", "awayOn", true)
    stub.RunTimers()
    markAway(true)
    whisper("you there?", "Lephoque")
    whisper("hello?", "Lephoque")
    markAway(false)
    T.eq(#sent, 1, "once")
    T.eq(sent[1][2], "Lephoque")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: at the keyboard the away message stays quiet", function()
    local sent = {}
    daylight(function()
        _G.C_ChatInfo = _G.C_ChatInfo or {}
        _G.C_ChatInfo.SendChatMessage = function(text, _, _, to) sent[#sent + 1] = { text, to } end
    end)
    DaylightUI:Set("Chat", "awayOn", true)
    stub.RunTimers()
    markAway(false)
    whisper("you there?", "Lephoque")
    T.eq(#sent, 0, "you're not away")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player sent "o7" to a friend, the friend said "yo", and got the away message
-- straight back.
T.test("chat whispers: someone you just whispered never gets the away message", function()
    local sent, bn = {}, {}
    daylight(function()
        _G.C_ChatInfo = _G.C_ChatInfo or {}
        _G.C_ChatInfo.SendChatMessage = function(text, _, _, to) sent[#sent + 1] = { text, to } end
        _G.BNSendWhisper = function(id, text) bn[#bn + 1] = { id, text } end
    end)
    DaylightUI:Set("Chat", "awayOn", true)
    stub.RunTimers()
    markAway(true)
    whisper("o7", "Lephoque", "CHAT_MSG_WHISPER_INFORM")
    whisper("yo", "Lephoque")
    T.eq(#sent, 0, "a character you whispered")
    stub.FireEvent("CHAT_MSG_BN_WHISPER_INFORM", "o7", "Friend", "", "", "", "", 0, 0, "", 0, 1, "", 7)
    stub.FireEvent("CHAT_MSG_BN_WHISPER", "yo", "Friend", "", "", "", "", 0, 0, "", 0, 2, "", 7)
    T.eq(#bn, 0, "a Battle.net friend you whispered")
    whisper("hello?", "Torvik")
    markAway(false)
    T.eq(#sent, 1, "anyone else still gets it")
    T.eq(sent[1][2], "Torvik")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: nothing sent while the game's chat is locked down", function()
    local sent
    daylight(function()
        _G.C_ChatInfo = _G.C_ChatInfo or {}
        _G.C_ChatInfo.SendChatMessage = function(text) sent = text end
        _G.C_ChatInfo.InChatMessagingLockdown = function() return true end
    end)
    local CH = stub.chatModule
    whisper("hi", "Lephoque")
    T.falsy(CH.Talk.Send(CH.Talk.Get("w:Lephoque"), "hello"))
    T.isnil(sent)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: kept for the character, back after a reload", function()
    daylight()
    whisper("see you tomorrow", "Lephoque")
    local saved = DaylightUI.DB.Character().whispers
    T.truthy(saved and saved["w:Lephoque"], "saved")
    T.eq(saved["w:Lephoque"].msgs[1].text, "see you tomorrow")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: the hub lists every conversation, searches them, shows the picked one", function()
    daylight()
    local CH = stub.chatModule
    whisper("got the key?", "Lephoque")
    whisper("thanks for the run", "Aelith")
    CH.Hub.Open()
    runMotion(1)
    T.truthy(CH.Hub.Frame():IsShown(), "open")
    T.truthy(CH.Hub.Showing("w:Aelith"), "the newest picked")
    T.eq(CH.Talk.Get("w:Aelith").unread, 0, "read")
    CH.Hub.Close()
    runMotion(1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A W.Confirm's two clicks, the second past its double-click guard.
local function confirm(b)
    b:GetScript("OnClick")(b)
    b.armedAt = -10
    b:GetScript("OnClick")(b)
end

-- The Clear link's click, then the pick in its menu.
local function clearLink(t)
    local picked
    local open = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, keys, values, _, onPick) picked = { keys[1], values[keys[1]], onPick } end
    t.links.clear:GetScript("OnClick")(t.links.clear)
    DaylightUI.Widgets.OpenMenu = open
    return picked
end

T.test("chat whispers: Clear on the card asks, then forgets the conversation and tucks the card away", function()
    daylight()
    local CH = stub.chatModule
    whisper("got the key?", "Lephoque")
    CH.Convo.Open("w:Lephoque")
    local ask = clearLink(CH.Convo.Thread())
    T.eq(ask[2], "Forget conversation")
    T.truthy(CH.Talk.Get("w:Lephoque"), "the click only asks")
    ask[3]("forget")
    T.falsy(CH.Talk.Get("w:Lephoque"), "gone")
    T.falsy(DaylightUI.DB.Character().whispers["w:Lephoque"], "gone from the saved ones too")
    T.falsy(CH.Convo.Key(), "the card tucked away")
    runMotion(1)
    T.eq(#shownTiles(), 0, "its tile with it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: Clear in the hub moves on to the next, and the last leaves an empty head", function()
    daylight()
    local CH = stub.chatModule
    whisper("got the key?", "Lephoque")
    whisper("thanks for the run", "Aelith")
    CH.Hub.Open()
    runMotion(1)
    local t = CH.Hub.Thread()
    clearLink(t)[3]("forget")
    T.falsy(CH.Talk.Get("w:Aelith"), "the picked one went")
    T.truthy(CH.Hub.Showing("w:Lephoque"), "on to the next")
    clearLink(t)[3]("forget")
    T.eq(#CH.Talk.List(), 0)
    T.falsy(t.links.clear:IsShown(), "nothing left to clear")
    T.falsy(t.portrait:IsShown(), "no old face left in the head")
    T.falsy(CH.Hub.Frame().clearAll:IsShown(), "Clear all goes too")
    whisper("back again", "Aelith")
    T.eq(#CH.Talk.Get("w:Aelith").msgs, 1, "a new whisper starts fresh")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: right-click a conversation in the hub list to pin or forget it", function()
    daylight()
    local CH = stub.chatModule
    whisper("got the key?", "Lephoque")
    whisper("thanks for the run", "Aelith")
    CH.Hub.Open()
    runMotion(1)
    local got
    local open = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, keys, values, _, onPick, _, opts)
        got = { keys = keys, values = values, onPick = onPick, opts = opts }
    end
    CH.Hub.RowMenu("w:Lephoque")
    DaylightUI.Widgets.OpenMenu = open
    T.eq(got.values.forget, "Forget conversation")
    T.truthy(got.opts and got.opts.atCursor, "opens at the cursor")
    got.onPick("pin")
    T.truthy(CH.Talk.Get("w:Lephoque").pinned, "pinned")
    got.onPick("forget")
    T.falsy(CH.Talk.Get("w:Lephoque"), "forgotten")
    T.truthy(CH.Hub.Showing("w:Aelith"), "the open one stays")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: the Clear menu acts on the one it was opened on, whatever is picked by then", function()
    daylight()
    local CH = stub.chatModule
    whisper("got the key?", "Lephoque")
    whisper("thanks for the run", "Aelith")
    CH.Hub.Open("w:Aelith")
    runMotion(1)
    local ask = clearLink(CH.Hub.Thread())
    CH.Hub.Open("w:Lephoque")
    ask[3]("forget")
    T.falsy(CH.Talk.Get("w:Aelith"), "the one asked about")
    T.truthy(CH.Talk.Get("w:Lephoque"), "not the one picked after")
    T.truthy(CH.Hub.Showing("w:Lephoque"), "still shown")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: Clear all keeps the pinned ones, in the hub and after a reload", function()
    daylight()
    local CH = stub.chatModule
    whisper("got the key?", "Lephoque")
    whisper("thanks for the run", "Aelith")
    whisper("hello", "Maren")
    CH.Talk.Pin(CH.Talk.Get("w:Lephoque"), true)
    CH.Hub.Open("w:Maren")
    runMotion(1)
    local all = CH.Hub.Frame().clearAll
    T.truthy(all:IsShown())
    confirm(all)
    T.falsy(CH.Talk.Get("w:Aelith"))
    T.falsy(CH.Talk.Get("w:Maren"))
    T.truthy(CH.Talk.Get("w:Lephoque"), "pinned stays")
    T.truthy(CH.Hub.Showing("w:Lephoque"), "the one shown went: on to what's left")
    T.falsy(all:IsShown(), "only pinned left: nothing to clear")
    local saved = DaylightUI.DB.Character().whispers
    T.falsy(saved["w:Maren"], "not saved either")
    T.truthy(saved["w:Lephoque"])
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: tiles at most, the conversation as tall as the chat, lines rising over a bottom input", function()
    local Box, box = daylight()
    local CH = stub.chatModule
    whisper("a", "One"); whisper("b", "Two"); whisper("c", "Three")
    T.eq(#shownTiles(), 3)
    DaylightUI:Set("Chat", "tilesMax", 2)
    stub.RunTimers()
    CH.Tiles.Refresh()
    runMotion(1)
    T.eq(#shownTiles(), 2, "two at most")
    CH.Convo.Open("w:Three")
    T.eq(CH.Convo.Card():GetHeight(), CH.Chat.PanelHeight(), "as tall as the chat")
    DaylightUI:Set("Chat", "boxInputAt", "bottom")
    stub.RunTimers()
    function ChatFrame1EditBox:HasFocus() return true end
    CH.Chat.Step(0.016)
    runMotion(1)
    local _, _, _, _, y = box:GetPoint(2)
    T.eq(y, Box.FOOT + 6, "typing: the footer up, the lines over it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: a conversation's Invite only for someone on your ruleset", function()
    daylight()
    local CH = stub.chatModule
    local was, wasBN = _G.GetRealmName, _G.C_BattleNet
    _G.GetRealmName = function() return "CAMWOW US1 Realm 8 PvP" end
    local T2 = CH.Thread
    T.truthy(T2.CanInvite({ name = "Same Name" }), "your realm")
    T.truthy(T2.CanInvite({ name = "Far Away-CAMWOWUS2Realm1PvP" }), "same rules elsewhere")
    T.falsy(T2.CanInvite({ name = "Far Away-CAMWOWUS2Realm1Hardcore" }), "other rules")
    local realm = "CAMWOW US2 Realm 1 PvP"
    _G.C_BattleNet = { GetAccountInfoByID = function(id)
        return { bnetAccountID = id, accountName = "Pal", gameAccountInfo = { gameAccountID = 5, clientProgram = "WoW",
            isOnline = true, characterName = "Pal", realmDisplayName = realm } }
    end }
    T.truthy(T2.CanInvite({ bn = 9 }), "a friend on your rules")
    realm = "CAMWOW US2 Realm 1 RP"
    T.falsy(T2.CanInvite({ bn = 9 }), "a friend on other rules")
    _G.GetRealmName, _G.C_BattleNet = was, wasBN
end)

-- The drawer's slides (their own driver frames, like the info panel's meter).
local function runDrawer(seconds)
    local _, b = stub.chatModule.Tiles.Sliders()
    for _ = 1, math.floor((seconds or 1) * 30) do
        for _, sl in ipairs({ b }) do
            if sl and sl.driver:IsShown() then stub.RunOnUpdate(sl.driver, 1 / 30) end
        end
    end
    runMotion(0.1)
end

T.test("chat whispers: a new whisper raises only its own tile; the mouse raises them all; a conversation folds out", function()
    daylight()
    local CH = stub.chatModule
    local holder = DaylightUIChat
    local over = false
    function holder:IsMouseOver() return over end
    local row = CH.Tiles.Column()
    local function settleTiles()
        for _ = 1, 30 do stub.Advance(1 / 30); stub.RunTimers(); runMotion(1 / 30) end
    end
    local function up()
        local out = {}
        for _, b in ipairs(CH.Tiles.Tiles()) do if b:IsShown() and (b.rise or 0) >= 1 then out[#out + 1] = b.key end end
        table.sort(out)
        return table.concat(out, ",")
    end
    whisper("hi", "Lephoque"); whisper("hey", "Aelith"); whisper("yo", "Torvik")
    settleTiles()
    T.eq(up(), "w:Aelith,w:Lephoque,w:Torvik", "three unread: three up")
    for _, k in ipairs({ "w:Lephoque", "w:Aelith", "w:Torvik" }) do CH.Talk.Read(CH.Talk.Get(k)) end
    stub.Advance(CH.Tiles.AWAKE + 1)
    CH.Chat.UpdateFade()
    settleTiles()
    T.eq(up(), "", "all read: all down")
    T.falsy(row:IsShown())
    whisper("you there?", "Aelith")
    settleTiles()
    T.eq(up(), "w:Aelith", "a new whisper: only its tile")
    local tile
    for _, b in ipairs(CH.Tiles.Tiles()) do if b.key == "w:Aelith" then tile = b end end
    local _, _, _, x, y = tile:GetPoint(1)
    T.eq(y, CH.Tiles.LIFT, "risen over the chat's top")
    T.eq(x, 0, "in the corner's spot")
    whisper("hello??", "Aelith")
    T.eq(tile.count:GetText(), "2", "again: the count goes up")
    over = true
    CH.Chat.UpdateFade()
    settleTiles()
    T.eq(up(), "w:Aelith,w:Lephoque,w:Torvik", "the mouse over the chat: all up")
    CH.Convo.Open("w:Lephoque")
    runDrawer(1)
    local _, cardSlide = CH.Tiles.Sliders()
    T.eq(cardSlide.p, 1)
    T.truthy(CH.Tiles.Drawer():GetWidth() > 100, "folded out")
    -- Narrow by default: the box keeps the whole width, with the links and Send
    -- in a row under it and the name as the head. Wide stays as before.
    local talk = CH.Convo.Thread()
    T.eq((CH.Convo.Size()), 200)
    T.eq(talk.narrow, true)
    local point, rel = talk.input:GetPoint(2)
    T.eq(point, "RIGHT")
    T.eq(rel, CH.Convo.Card(), "the box runs the whole width")
    local _, under = talk.links.all:GetPoint(1)
    T.eq(under, CH.Convo.Card(), "All sits by the footer")
    -- The newest line stands right above the box, whichever way the footer lies.
    local function atNewest(t, why)
        local _, _, _, _, y = t.input:GetPoint(1)
        local view = CH.Chat.PanelHeight() - CH.Thread.HEAD - 4 - (y + DaylightUI.Widgets.INPUT_H + 6)
        T.eq(t.list:GetVerticalScroll(), t.child:GetHeight() - view, why)
    end
    for i = 1, 30 do whisper("line " .. i, "Lephoque") end
    atNewest(talk, "narrow: a new line scrolls all the way down")
    CH.Convo.Close()
    runDrawer(1)
    DaylightUI:Set("Chat", "cardWidth", 320)
    stub.RunTimers()
    CH.Convo.Open("w:Lephoque")
    runDrawer(1)
    T.eq(talk.narrow, false)
    point, rel = talk.input:GetPoint(2)
    T.eq(rel, talk.send, "wide: Send beside the box")
    local _, near = talk.links.all:GetPoint(1)
    T.eq(near, talk.close, "wide: the links in the head")
    whisper("one more", "Lephoque")
    atNewest(talk, "wide: the same")
    DaylightUI:Set("Chat", "cardWidth", 200)
    stub.RunTimers()
    CH.Convo.Close()
    runDrawer(1)
    T.eq(cardSlide.p, 0)
    T.falsy(CH.Convo.Card():IsShown(), "hidden once folded in")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: a conversation opens above the chat, drags away and sizes by its corner", function()
    daylight()
    local CH = stub.chatModule
    whisper("hi", "Aelith")
    DaylightUI:Set("Chat", "cardAt", "above")
    stub.RunTimers()
    CH.Convo.Open("w:Aelith")
    runDrawer(1)
    local drawer, card = CH.Tiles.Drawer(), CH.Convo.Card()
    local point, rel, relPoint, _, y = drawer:GetPoint(1)
    T.eq(point, "BOTTOMRIGHT", "above: on the chat's corner")
    T.eq(rel, CH.Chat.Panel())
    T.eq(relPoint, "TOPRIGHT")
    T.eq(y, CH.Tiles.AboveTiles(), "over the tiles' row")
    T.eq(drawer:GetHeight(), 300, "its own height")
    T.eq(card:GetHeight(), 300)
    T.eq(CH.Convo.GripCorner(), "TOPLEFT", "the grip on the corner away from the chat")
    -- Dragged by its head, it stays where it was let go.
    CH.Convo.moving = true
    local wasUi = UIParent.__center
    UIParent.__center = { 960, 540 }
    drawer.__center = { 1100, 700 }   -- where it was let go (the fake game only knows a middle when told)
    card:GetScript("OnDragStop")(card)
    UIParent.__center = wasUi
    stub.RunTimers()
    T.eq(DaylightUI:Get("Chat", "cardAt"), "free", "dragged: it opens there from now on")
    T.truthy(CH.Convo.Spot(), "its spot kept")
    runDrawer(1)
    point, rel = drawer:GetPoint(1)
    T.eq(point, "CENTER")
    T.eq(rel, UIParent, "on the screen, not the chat")
    -- Its corner sizes it, and width and height are kept.
    local grip = CH.Convo.Grip()
    grip:GetScript("OnMouseDown")(grip)
    T.truthy(CH.Convo.sizing)
    drawer:SetSize(420, 360)
    grip:GetScript("OnMouseUp")(grip)
    stub.RunTimers()
    T.eq(DaylightUI:Get("Chat", "cardWidth"), 420)
    T.eq(DaylightUI:Get("Chat", "cardHeight"), 360)
    T.eq(card:GetWidth(), 420, "the card fills it")
    T.eq(CH.Convo.Thread().narrow, false, "wide now: links in the head")
    -- Locked chat: no drag, no sizing.
    DaylightUI:Set("Chat", "locked", true)
    stub.RunTimers()
    grip:GetScript("OnMouseDown")(grip)
    T.falsy(CH.Convo.sizing, "locked: the grip does nothing")
    DaylightUI:Set("Chat", "locked", false)
    DaylightUI:Set("Chat", "cardAt", "side")
    DaylightUI:Set("Chat", "cardWidth", 200)
    stub.RunTimers()
    CH.Convo.Close()
    runDrawer(1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: the log keeps the newest lines, letting the oldest go in batches", function()
    local Box = daylight()
    local total = Box.MAX + Box.TRIM + 1
    for i = 1, total do Box.Push({ "line " .. i, 1, 1, 1, "say" }) end
    local log = Box.Log()
    T.eq(#log, Box.MAX, "back to MAX once past MAX + TRIM")
    T.eq(log[1][1], "line " .. (total - Box.MAX + 1), "the oldest kept")
    T.eq(log[#log][1], "line " .. total, "the newest last")
    Box.Push({ "one more", 1, 1, 1, "say" })
    T.eq(#log, Box.MAX + 1, "then grows again until the next batch")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a busy tab's count lays the tab row out again only when its width can change", function()
    local Box = daylight()
    local guild
    for b in pairs(Box.Labels()) do if b.words == (_G.GUILD or "Guild") then guild = b end end
    local real, n = Box.LayoutTabs, 0
    Box.LayoutTabs = function(...) n = n + 1 return real(...) end
    for i = 1, 12 do said(ChatFrame1, "g" .. i, "CHAT_MSG_GUILD", 100 + i) end
    Box.LayoutTabs = real
    T.eq(guild.dot:GetText(), "12")
    T.eq(n, 2, "the count showing (1), then its second digit (10)")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's button as it comes, in ChatFrame1's hidden side bar. Showing it from
-- addon code runs its OnShow there, which sets a language when none is set yet
-- (ValidateSelectedLanguage), and that write would taint the box's sending.
local function menuButton()
    local btn = CreateFrame("Button", "ChatFrameMenuButton", ChatFrame1.buttonFrame)
    btn.shows = 0
    btn:SetScript("OnShow", function(self)
        self.shows = self.shows + 1
        self.wroteLanguage = DEFAULT_CHAT_FRAME.editBox.languageID == nil
    end)
    return btn
end

T.test("chat daylight: the game's chat menu button sits on the header's icon once your language is set", function()
    local Box = daylight()
    local game = DEFAULT_CHAT_FRAME
    _G.DEFAULT_CHAT_FRAME = ChatFrame1
    ChatFrame1.editBox = { }
    local btn = menuButton()
    local Menu = stub.chatModule.ChatMenu
    local icon = Box.main.icons.menu

    Menu.Pass()
    T.eq(btn:GetParent(), ChatFrame1.buttonFrame, "no language yet: it stays hidden in the game's side bar")

    ChatFrame1.editBox.languageID, ChatFrame1.editBox.language = 7, "Common"
    Menu.Pass()
    T.truthy(btn:GetParent() ~= ChatFrame1.buttonFrame, "seated")
    T.truthy(btn:IsVisible())
    T.falsy(btn.wroteLanguage, "shown only with a language set: nothing written by the game's OnShow")
    T.eq(btn:GetAlpha(), 0, "unseen: the icon is what shows")
    T.truthy(btn:IsMouseEnabled(), "and the click is the game's")
    T.truthy(btn:GetFrameLevel() > icon:GetFrameLevel())

    local on = DaylightUI.Motion.On
    DaylightUI.Motion.On = function() return false end
    btn:GetScript("OnEnter")(btn)
    T.eq(icon.over, 1, "hover reaches the icon")
    btn:GetScript("OnLeave")(btn)
    DaylightUI.Motion.On = on

    T.truthy(string.find(Menu.Tip(), "emotes", 1, true))
    _G.GetNumLanguages = function() return 2 end
    T.truthy(string.find(Menu.Tip(), "Common", 1, true), "more than one language: says which you speak")
    _G.GetNumLanguages = nil

    local shows = btn.shows
    DaylightUI:Set("Chat", "menuButton", false)
    stub.RunTimers()
    Menu.Pass()
    T.falsy(btn:IsMouseEnabled(), "switched off: no click left behind")
    DaylightUI:Set("Chat", "menuButton", true)
    stub.RunTimers()
    Menu.Pass()
    T.truthy(btn:IsMouseEnabled(), "back on")
    T.eq(btn.shows, shows, "never shown again: only its mouse goes on and off")

    _G.DEFAULT_CHAT_FRAME = game
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: the voice chat icon is off by default and opens the game's Chat Channels window", function()
    local Box = daylight()
    local icon = Box.main.icons.voice
    local M = DaylightUI.Motion
    local on = M.On
    M.On = function() return false end
    T.falsy(icon:IsShown(), "off by default")
    DaylightUI:Set("Chat", "voiceButton", true)
    stub.RunTimers()
    T.truthy(icon:IsShown(), "switched on: the headset shows")

    -- The game's window, as Blizzard_Channels makes it (ToggleFrame).
    local game = _G.ChannelFrame
    local f = CreateFrame("Frame", "ChannelFrame", UIParent)
    f:Hide()
    function f:Toggle() if self:IsShown() then self:Hide() else self:Show() end end
    icon:GetScript("OnClick")(icon, "LeftButton")
    T.truthy(f:IsShown(), "a click opens it")
    icon:GetScript("OnClick")(icon, "LeftButton")
    T.falsy(f:IsShown(), "again closes it")

    _G.ChannelFrame = nil
    icon:GetScript("OnClick")(icon, "LeftButton")   -- no window, and nothing breaks
    _G.ChannelFrame = game
    DaylightUI:Set("Chat", "voiceButton", false)
    stub.RunTimers()
    T.falsy(icon:IsShown(), "off again")
    M.On = on
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: the Copy icon follows its switch, the whispers bubble its setting, the rest close up", function()
    local Box = daylight()
    local icons = Box.main.icons
    local M = DaylightUI.Motion
    local on = M.On
    M.On = function() return false end   -- the end of each fade
    local function spot(b) return select(4, b:GetPoint()) end
    T.truthy(icons.copy:IsShown(), "on by default")
    T.truthy(icons.whispers:IsShown(), "on by default")
    local bubbleAt = spot(icons.whispers)

    DaylightUI:Set("Chat", "copyButton", false)
    stub.RunTimers()
    T.falsy(icons.copy:IsShown(), "switched off: the icon goes")
    T.truthy(icons.whispers:IsShown())
    T.truthy(spot(icons.whispers) > bubbleAt, "the bubble moves up into its place")

    DaylightUI:Set("Chat", "whispersIn", "chat")
    stub.RunTimers()
    T.falsy(icons.whispers:IsShown(), "whispers only in the chat: no bubble")
    T.falsy(icons.whispers.count:IsVisible(), "its count goes with it")
    T.truthy(icons.lock:IsShown())
    T.truthy(icons.options:IsShown())

    DaylightUI:Set("Chat", "whispersIn", "both")
    DaylightUI:Set("Chat", "whispersButton", false)
    stub.RunTimers()
    T.falsy(icons.whispers:IsShown(), "its own switch off: no bubble")

    DaylightUI:Set("Chat", "copyButton", true)
    DaylightUI:Set("Chat", "whispersButton", true)
    stub.RunTimers()
    T.truthy(icons.copy:IsShown(), "back on")
    T.truthy(icons.whispers:IsShown(), "back on")
    T.eq(spot(icons.whispers), bubbleAt, "back in its place")
    M.On = on
end)

T.test("chat daylight: the header's icons and the footer: counts on tabs, lock, options, the field", function()
    local Box, box = daylight()
    local CH = stub.chatModule
    -- A tab's count goes up with each new line for it and clears when picked.
    said(ChatFrame1, "g1", "CHAT_MSG_GUILD", 1)
    said(ChatFrame1, "g2", "CHAT_MSG_GUILD", 2)
    local guild
    for b in pairs(Box.Labels()) do if b.words == (_G.GUILD or "Guild") then guild = b end end
    T.eq(guild.dot:GetText(), "2", "two new in Guild")
    Box.Pick(2)
    T.eq(guild.unread, 0, "looked at: cleared")
    -- Lock removes the corner grip.
    Box.main.icons.lock:GetScript("OnClick")(Box.main.icons.lock, "LeftButton")
    stub.RunTimers()
    T.truthy(DaylightUI:Get("Chat", "locked"))
    CH.Chat.UpdateFade()
    T.falsy(DaylightUIChatGrip:IsMouseEnabled(), "locked: no grip")
    -- Options opens the chat page.
    local shown
    DaylightUI.OptionsPanel.Show = function(id) shown = id end
    Box.main.icons.options:GetScript("OnClick")(Box.main.icons.options, "LeftButton")
    T.eq(shown, "Chat.chat")
    -- The footer never runs the game's typing code. A click calling its Enter or
    -- OpenChat from addon code would send a typed /cast tainted.
    local ran
    ChatFrame1EditBox:SetScript("OnEnterPressed", function() ran = true end)
    _G.ChatFrameUtil = { OpenChat = function() ran = true end }
    function ChatFrame1EditBox:HasFocus() return true end
    local foot = Box.Field():GetParent()
    T.isnil(foot.send, "no Send of ours: Enter sends")
    local click = Box.Field():GetScript("OnClick")
    if click then click(Box.Field(), "LeftButton") end
    T.isnil(ran, "the field's click runs nothing of the game's")
    CH.Chat.Hold(true)
    local _, rel = ChatFrame1EditBox:GetPoint(1)
    T.eq(rel, Box.Field(), "the game's box over the footer's field")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: floating, a new whisper's tile fades in for a bit though the panel is gone, then goes with it", function()
    daylight()
    local CH = stub.chatModule
    DaylightUI:Set("Chat", "hides", "always")
    function DaylightUIChat:IsMouseOver() return false end
    CH.Chat.UpdateFade()
    runMotion(1)
    T.eq(CH.Chat.Panel():GetAlpha(), 0, "floating: the panel is gone")
    local row = CH.Tiles.Column()
    local function seen() return row:IsIgnoringParentAlpha() and row:GetAlpha() or row:GetEffectiveAlpha() end
    T.truthy(seen() == 0, "and the row with it")
    whisper("you there?", "Aelith")
    local first = seen()
    T.truthy(first < 0.5, "it starts faint: it fades in")
    runMotion(1)
    T.eq(seen(), 1, "shown over the floating chat")
    stub.Advance(CH.Tiles.PREVIEW - 1)
    CH.Chat.UpdateFade()
    T.eq(seen(), 1, "still there a few seconds on")
    stub.Advance(2)
    CH.Chat.UpdateFade()
    runMotion(1)
    T.eq(seen(), 0, "then it goes with the panel")
    T.falsy(row:IsIgnoringParentAlpha(), "and follows the panel again")
    -- Clicked while it shows, its conversation holds the panel it rides on.
    CH.Convo.Open("w:Aelith")
    CH.Chat.UpdateFade()
    runMotion(1)
    T.eq(CH.Chat.Panel():GetAlpha(), 1, "a conversation open: the panel stays")
    CH.Convo.Close()
    runMotion(1)
end)

T.test("chat whispers: a Battle.net friend's tile shows their name's letters, Bn only when the game knows no tag", function()
    local tag = "Siberiac#1234"
    daylight(function()
        _G.C_BattleNet = { GetAccountInfoByID = function() return { accountName = "|Kq12|k", battleTag = tag } end }
    end)
    local function bn(id)
        stub.FireEvent("CHAT_MSG_BN_WHISPER", "hi", "|Kq12|k", "", "", "", "", 0, 0, "", 0, 1, "", id)
        for _, b in ipairs(shownTiles()) do
            if b.key == "bn:" .. id then return b.letter:GetText() or b.slices[1]:GetText() end
        end
    end
    T.eq(bn(77), "Si", "Si for Siberiac, not Bn")
    tag = nil
    T.eq(bn(78), "Bn", "no tag known")
    _G.C_BattleNet = nil
end)

T.test("chat whispers: a tile shows two letters; its X (on hover) closes it, the conversation kept", function()
    daylight()
    local CH = stub.chatModule
    whisper("hi", "Thornwick")
    stub.RunTimers()
    local tile = shownTiles()[1]
    T.eq(tile.letter:GetText() or tile.slices[1]:GetText(), "Th", "Th for Thornwick")
    fakeTooltip()
    tile:GetScript("OnEnter")(tile)
    runMotion(0.5)
    T.eq(tile.close:GetAlpha(), 1, "the X fades in")
    tile.close:GetScript("OnClick")(tile.close, "LeftButton")
    stub.RunTimers()
    runMotion(1)
    T.eq(#shownTiles(), 0, "gone")
    T.truthy(CH.Talk.Get("w:Thornwick"), "still in the hub")
    whisper("hello?", "Thornwick")
    stub.RunTimers()
    T.eq(#shownTiles(), 1, "a new whisper brings it back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: the footer shows only while you type, the lines rising for it", function()
    local Box, box = daylight()
    local CH = stub.chatModule
    local foot = Box.Field():GetParent()
    T.falsy(foot:IsShown(), "at rest: no footer")
    local _, _, _, _, y = box:GetPoint(2)
    T.eq(y, 0, "the lines down to the bottom")
    function ChatFrame1EditBox:HasFocus() return true end
    CH.Chat.Step(0.016)
    runMotion(1)
    T.truthy(foot:IsShown(), "typing: the footer")
    T.eq(foot:GetAlpha(), 1)
    function ChatFrame1EditBox:HasFocus() return false end
    CH.Chat.Step(0.016)
    runMotion(1)
    T.falsy(foot:IsShown(), "done: gone again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: a whisper to a name with letters beyond English is made one; plain names left to the game", function()
    login()
    local Tell = stub.chatModule.Tell
    T.eq(select(1, Tell.Parse("/w Lephoque Mapoussé hi")), "Lephoque Mapoussé")
    T.eq(select(2, Tell.Parse("/w Lephoque Mapoussé hi there")), "hi there")
    T.isnil(Tell.Parse("/w Lephoque Mapoussé"), "still typing the last name")
    T.isnil(Tell.Parse("/w Bob Smith hi"), "plain English names: the game's")
    T.isnil(Tell.Parse("/w Zoë hi"), "one word, not Chinese/Korean: still typing")
    T.isnil(Tell.Parse("/w 김 철수"), "Korean: still typing the last name")
    T.eq(select(1, Tell.Parse("/w 김 철수 안녕")), "김 철수", "Korean: first and last name")
    T.eq(select(2, Tell.Parse("/w 张 三 你好")), "你好", "Chinese: the message after both")
    -- The box after a space: the game's own methods make it a whisper.
    local eb = ChatFrame1EditBox
    local got = {}
    function eb:SetTellTarget(t) got.target = t end
    function eb:SetChatType(t) got.type = t end
    function eb:UpdateHeader() got.header = true end
    eb:SetText("/w Lephoque Mapoussé hi")
    eb:GetScript("OnKeyDown")(eb, "SPACE")
    stub.RunTimers()
    T.eq(got.target, "Lephoque Mapoussé")
    T.eq(got.type, "WHISPER")
    T.eq(eb:GetText(), "hi", "the message left in the box")
    T.truthy(got.header)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: lines in Russian, Chinese and Korean are never taken for gold adverts; money signs still are", function()
    local _, box = daylight()
    local Extras = stub.chatModule.Extras
    for _, text in ipairs({ "ищет 2 dd в ZG", "Нужен танк 1 место", "组队 2 dd 来", "파티 2 dd 구함" }) do
        T.falsy(Extras.IsSpam("trade", "Someone", text), text)
    end
    T.truthy(Extras.IsSpam("trade", "Seller", "1000 gold for €5"), "a euro price")
    T.truthy(Extras.IsSpam("trade", "Seller", "1000 gold for £5"), "a pound price")
    T.truthy(Extras.IsSpam("trade", "Seller", "1000 gold for $5"), "a dollar price")
    channelLine(ChatFrame1, "ищет 2 dd в ZG", "Иван", 1)
    T.eq(boxTexts(box)[1], "ищет 2 dd в ZG", "shown, not hidden as spam")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat classic: the Daylight box's extras stay off (no alert sound, no spam hiding, no away answer)", function()
    local played, sent = {}, {}
    local Box = daylight(function()
        _G.PlaySoundFile = function(f) if string.find(f, "whisper-", 1, true) then played[#played + 1] = f end end
        _G.C_ChatInfo = _G.C_ChatInfo or {}
        _G.C_ChatInfo.SendChatMessage = function(text, _, _, to) sent[#sent + 1] = { text, to } end
    end)
    DaylightUI:Set("Chat", "awayOn", true)
    DaylightUI:Set("Chat", "style", "classic")
    stub.RunTimers()
    local shines = 0
    local Feel = stub.chatModule.Feel
    local realShine = Feel.Shine
    Feel.Shine = function(...) shines = shines + 1 return realShine(...) end
    said(ChatFrame1, "is " .. UnitName("player") .. " coming?", "CHAT_MSG_GUILD", 1)
    Feel.Shine = realShine
    T.eq(#played, 0, "no alert sound in Classic: " .. table.concat(played, ","))
    T.eq(shines, 0, "no light along the tabs")
    channelLine(ChatFrame1, "cheap gold www.gold.example", "Spammer", 2)
    T.eq(Box.spam, 0, "nothing hidden as spam")
    T.eq(Box.Log()[#Box.Log()][1], "cheap gold www.gold.example", "the line kept as heard")
    whisper("you there?", "Lephoque")
    T.eq(#sent, 0, "no away answer in Classic")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: in their own window, a locked (secret) whisper and away/offline notices still reach the chat", function()
    local _, box = daylight()
    DaylightUI:Set("Chat", "whispersIn", "window")
    stub.RunTimers()
    local s = stub.Secret("[Lephoque] whispers: locked")
    ChatFrame1:AddMessage(s, 1, 0.5, 1, nil, nil, nil, "CHAT_MSG_WHISPER", { s, "Lephoque", n = 14 })
    T.eq(box:GetNumMessages(), 1, "a secret whisper isn't kept as a conversation: it shows in the chat")
    ChatFrame1:AddMessage("Lephoque is Away: brb", 1, 0.5, 1, nil, nil, nil, "CHAT_MSG_AFK", { "brb", "Lephoque", n = 14 })
    T.eq(box:GetNumMessages(), 2, "an away notice shows")
    ChatFrame1:AddMessage("Aelith is offline.", 1, 0.5, 1, nil, nil, nil, "CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE", { "", "Aelith", n = 14 })
    T.eq(box:GetNumMessages(), 3, "an offline notice shows")
    ChatFrame1:AddMessage("[Lephoque] whispers: hi", 1, 0.5, 1, nil, nil, nil, "CHAT_MSG_WHISPER", { "hi", "Lephoque", n = 14 })
    T.eq(box:GetNumMessages(), 3, "a plain whisper: its conversation only")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player's line as the game sends it: the sender is a link in the line, the 2nd
-- argument is their name and the 12th their GUID (ChatFrameOverrides).
local function spoke(cf, sender, guid, words, lineId)
    local args = { words, sender, n = 14 }
    args[11], args[12] = lineId, guid
    local line = "|Hplayer:" .. sender .. ":" .. lineId .. "|h[" .. sender .. "]|h: " .. words
    cf:AddMessage(line, 1, 1, 1, 3, nil, nil, "CHAT_MSG_GUILD", args)
end

T.test("chat daylight: the sound for lit-up words starts off", function()
    local played = {}
    local Box = daylight(function()
        _G.PlaySoundFile = function(f) if string.find(f, "whisper-", 1, true) then played[#played + 1] = f end end
    end)
    T.eq(DaylightUI:Get("Chat", "alertSound"), false, "off unless picked")
    said(ChatFrame1, "is " .. UnitName("player") .. " coming?", "CHAT_MSG_GUILD", 1)
    T.truthy(Box.Log()[#Box.Log()].alert, "still lit")
    T.eq(#played, 0, "no sound: " .. table.concat(played, ","))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: your own lines never light up, whatever form the game gives your name in", function()
    local Box = daylight()
    local realGUID = _G.UnitGUID
    _G.UnitGUID = function(u) if u == "player" then return "Player-1-AAA" end return realGUID(u) end
    local me = UnitName("player")
    spoke(ChatFrame1, me, "Player-1-AAA", "hello", 1)
    T.falsy(Box.Log()[#Box.Log()].alert, "your name only as the sender")
    spoke(ChatFrame1, me .. " Money", "Player-1-AAA", "this is " .. me .. " speaking", 2)
    T.falsy(Box.Log()[#Box.Log()].alert, "your name in your own words, a surname on the sender")
    spoke(ChatFrame1, me .. "-Money", "Player-1-AAA", "this is " .. me .. " speaking", 3)
    T.falsy(Box.Log()[#Box.Log()].alert, "the same with a dash")
    _G.UnitGUID = realGUID
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: only words people typed count: not a sender's name, nothing that isn't lit", function()
    local Box = daylight()
    local me = UnitName("player")
    spoke(ChatFrame1, me .. " Other", "Player-2-BBB", "hello", 1)
    T.falsy(Box.Log()[#Box.Log()].alert, "someone sharing your first name, not saying it")
    spoke(ChatFrame1, "Torvik", "Player-3-CCC", "hello " .. me, 2)
    T.truthy(Box.Log()[#Box.Log()].alert, "someone else saying it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a secret GUID is left alone", function()
    local Box = daylight()
    spoke(ChatFrame1, "Torvik", stub.Secret("Player-3-CCC"), "hello " .. UnitName("player"), 1)
    T.truthy(Box.Log()[#Box.Log()].alert, "the line still lights by its words")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a name starting or ending in an accented letter still lights up, never inside a longer word", function()
    local Box, box = daylight()
    local realName = _G.UnitName
    for _, me in ipairs({ "Émile", "Mapoussé" }) do
        _G.UnitName = function(u) if u == "player" then return me end return realName(u) end
        local n = #Box.Log()
        said(ChatFrame1, "is " .. me .. " coming?", "CHAT_MSG_GUILD", 300 + #me)
        T.truthy(Box.Log()[n + 1].alert, me .. " lit")
        said(ChatFrame1, "x" .. me .. "é here", "CHAT_MSG_GUILD", 400 + #me)
        T.falsy(Box.Log()[n + 2].alert, me .. " inside a longer word: not")
    end
    _G.UnitName = realName
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: a conversation is saved once something is said; old empty ones dropped at login", function()
    daylight()
    local CH = stub.chatModule
    local saved = DaylightUI.DB.Character().whispers
    whisper("hi", "Torvik", "CHAT_MSG_WHISPER_INFORM")
    T.truthy(saved["w:Torvik"], "saved once something is said")
    saved["w:Empty"] = { name = "Empty", msgs = {}, unread = 0 }
    CH.Talk.Load()
    T.isnil(saved["w:Empty"], "an empty one from before dropped")
    T.isnil(CH.Talk.Get("w:Empty"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat classic: /dui whispers points to the Daylight chat box instead of a hub that can't keep up", function()
    daylight()
    local CH = stub.chatModule
    DaylightUI:Set("Chat", "style", "classic")
    stub.RunTimers()
    local said = {}
    local realPrint = DaylightUI.Print
    DaylightUI.Print = function(text) said[#said + 1] = text end
    CH.Hub.Command()
    DaylightUI.Print = realPrint
    T.falsy(CH.Hub.Frame() and CH.Hub.Frame():IsShown(), "no hub in Classic")
    T.truthy(said[1] and string.find(said[1], "/dui chat daylight", 1, true), "says how to get it")
    DaylightUI:Set("Chat", "style", "daylight")
    stub.RunTimers()
    CH.Hub.Command()
    runMotion(1)
    T.truthy(CH.Hub.Frame():IsShown(), "in Daylight: the hub")
    DaylightUI:Set("Chat", "style", "classic")
    stub.RunTimers()
    runMotion(1)
    T.falsy(DaylightUI.Win.IsOpen(CH.Hub.Frame()), "switching to Classic closes it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a tab's unread count stays with its tab when another is removed or moved", function()
    local Box = daylight()
    local Tabs = stub.chatModule.Tabs
    local function countOf(name)
        for b in pairs(Box.Labels()) do if b.words == name and b:IsShown() then return b.unread or 0 end end
    end
    said(ChatFrame1, "g1", "CHAT_MSG_GUILD", 501)
    ChatFrame1:AddMessage("You receive loot: [Linen]", 0, 0.7, 0, 2)
    ChatFrame1:AddMessage("You receive loot: [Wool]", 0, 0.7, 0, 2)
    local guild, loot = _G.GUILD or "Guild", _G.LOOT or "Loot"
    T.eq(countOf(guild), 1)
    T.eq(countOf(loot), 2)
    local trade = _G.TRADE or "Trade"
    Tabs.Remove(2)     -- Guild gone, so Trade and Loot shift left
    stub.RunTimers()
    T.isnil(countOf(guild), "Guild gone")
    T.eq(countOf(trade), 0, "Trade never had any (not Guild's)")
    T.eq(countOf(loot), 2, "Loot keeps its two")
    Box.Pick(1)
    said(ChatFrame1, "g2", "CHAT_MSG_GUILD", 502)
    Tabs.Move(2, 1)    -- Trade right of Loot (Trade picked)
    stub.RunTimers()
    T.eq(countOf(loot), 2, "Loot's count moved with it")
    T.eq(countOf(trade), 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: the spam note isn't saved in the history (it would come back as a dead line)", function()
    local Box = daylight()
    channelLine(ChatFrame1, "cheap gold www.gold.example", "Spammer", 1)
    T.eq(Box.spam, 1)
    said(ChatFrame1, "guild line", "CHAT_MSG_GUILD", 2)
    stub.FireEvent("PLAYER_LOGOUT")
    local saved = DaylightUI.DB.Character().chatHistory
    T.eq(#saved.box, 1, "only the real line")
    T.eq(saved.box[1][1], "guild line")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: an error in reading a line never reaches the game's own AddMessage", function()
    local Box = daylight()
    local real = Box.Feed
    Box.Feed = function() error("boom") end
    local ok = pcall(ChatFrame1.AddMessage, ChatFrame1, "a line", 1, 1, 1, 1)
    Box.Feed = real
    T.truthy(ok, "the game's AddMessage went on")
    T.truthy(stub.errors[1] and string.find(tostring(stub.errors[1]), "boom", 1, true), "reported as ours")
    for i = #stub.errors, 1, -1 do stub.errors[i] = nil end
end)

-- The game hands the predicate the entry unpacked, so its message comes first, and
-- that can be a secret line (the error in game: "Spammed" > dropNote).
T.test("chat daylight: a new spam note replaces the old one, with a secret line in the list", function()
    local Box, box = daylight()
    ChatFrame1:AddMessage(stub.Secret("a locked line"), 1, 1, 1, 1)
    channelLine(ChatFrame1, "cheap gold www.gold.example", "Spammer1", 701)
    stub.Advance(Box.NOTE_GAP + 0.1)
    channelLine(ChatFrame1, "cheap gold www.more.example", "Spammer2", 702)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local notes = 0
    for _, t in ipairs(boxTexts(box)) do
        if type(t) == "string" and string.find(t, "spam line", 1, true) then notes = notes + 1 end
    end
    T.eq(notes, 1, "one note")
end)

-- Shift-click a name, or send a line, and the game answers with a system line
-- ("[Bob]: Level 12...", "No player named..."), which a Trade tab doesn't show.
local function systemLine(text) ChatFrame1:AddMessage(text, 1, 1, 0, 1, nil, nil, "CHAT_MSG_SYSTEM", { text, "", n = 14 }) end

T.test("chat daylight: a Shift-clicked name's /who answer shows on the tab you're on, and stays there", function()
    local Box, box = daylight()
    Box.Pick(3)
    local was, wasRef = _G.IsModifiedClick, _G.SetItemRef
    _G.IsModifiedClick, _G.SetItemRef = function(what) return what == "CHATLINK" end, function() end
    systemLine("Dave has come online.")
    T.eq(#boxTexts(box), 0, "a system line alone stays out of Trade")
    box:GetScript("OnHyperlinkClick")(box, "player:Bob:7:CHANNEL:2", "[Bob]", "LeftButton")
    systemLine("[Bob]: Level 12 Human Mage")
    T.truthy(string.find(boxTexts(box)[1] or "", "Level 12", 1, true), "the answer shows")
    stub.Advance(Box.ANSWER + 0.1)
    systemLine("Dave has gone offline.")
    T.eq(#boxTexts(box), 1, "only the answer, not what comes later")
    Box.Pick(2)
    Box.Pick(3)
    T.eq(#boxTexts(box), 1, "still on the tab after coming back")
    _G.IsModifiedClick, _G.SetItemRef = was, wasRef
    Box.Pick(1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a line you send gets its answer on the tab you're on; a plain click on a name doesn't ask", function()
    local Box, box = daylight()
    Box.Pick(3)
    local was, wasRef = _G.IsModifiedClick, _G.SetItemRef
    _G.IsModifiedClick, _G.SetItemRef = function() return false end, function() end
    box:GetScript("OnHyperlinkClick")(box, "player:Bob:7:CHANNEL:2", "[Bob]", "LeftButton")
    systemLine("Dave has come online.")
    T.eq(#boxTexts(box), 0, "a whisper click is no question")
    _G.IsModifiedClick, _G.SetItemRef = was, wasRef
    stub.chatModule.Recall.OnSend({ GetText = function() return "/who Bob" end })
    systemLine("No player named 'Bob' is currently playing.")
    T.truthy(string.find(boxTexts(box)[1] or "", "No player", 1, true), "the answer shows")
    Box.Pick(1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: the game's chat scroll keys move the box, follow a rebind and leave with Classic", function()
    local Box, box
    Box, box = daylight(function()
        stub.bindings.CHATPAGEUP, stub.bindings.CHATPAGEDOWN, stub.bindings.CHATBOTTOM = { "PAGEUP" }, { "PAGEDOWN" }, { "SHIFT-PAGEDOWN" }
    end)
    for i = 1, 30 do said(ChatFrame1, "line " .. i, "CHAT_MSG_GUILD", 800 + i) end
    local function press(key)
        local o = stub.overrides[key]
        T.truthy(o, key .. " is ours")
        _G[o.click]:GetScript("OnClick")(_G[o.click], o.button)
    end
    press("PAGEUP")
    T.truthy(box:GetScrollOffset() > 0, "paged up")
    press("PAGEDOWN")
    T.eq(box:GetScrollOffset(), 0, "paged down")
    press("PAGEUP")
    press("SHIFT-PAGEDOWN")
    T.eq(box:GetScrollOffset(), 0, "to the bottom")
    stub.bindings.CHATPAGEUP = { "HOME" }
    stub.FireEvent("UPDATE_BINDINGS")
    T.truthy(stub.overrides.HOME and not stub.overrides.PAGEUP, "a rebound key follows")
    DaylightUI:Set("Chat", "style", "classic")
    T.truthy(not stub.overrides.HOME, "Classic: the keys are the game's again")
    DaylightUI:Set("Chat", "style", "daylight")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a burst of hidden adverts redraws the spam note once, not once per line", function()
    local Box, box = daylight()
    local real, redraws = box.RemoveMessagesByPredicate, 0
    box.RemoveMessagesByPredicate = function(...) redraws = redraws + 1 return real(...) end
    for i = 1, 20 do channelLine(ChatFrame1, "cheap gold www.gold" .. i .. ".example", "Spammer" .. i, 600 + i) end
    T.truthy(redraws <= 1, "one redraw at most during the burst: " .. redraws)
    T.eq(Box.spam, 20, "every one counted")
    stub.Advance(Box.NOTE_GAP + 0.1)
    stub.RunTimers()
    box.RemoveMessagesByPredicate = real
    local texts, notes = boxTexts(box), 0
    for _, t in ipairs(texts) do if string.find(t, "spam lines hidden", 1, true) then notes = notes + 1 end end
    T.eq(notes, 1, "one note")
    T.truthy(string.find(texts[#texts], "20 spam lines hidden", 1, true), "saying 20, the newest line")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: the hub keeps its spot the window kit's way (an old spot moved over, /dui reset forgets it)", function()
    daylight()
    local CH = stub.chatModule
    local db = DaylightUI:GetModule("Chat").db
    db.hubSpot = { 300, 600 }
    CH.Hub.Open()
    runMotion(1)
    T.isnil(db.hubSpot, "the old setting gone")
    T.eq(db.spot and db.spot[1], 300, "moved over")
    local refreshed = 0
    local real = CH.Chat.Refresh
    CH.Chat.Refresh = function(...) refreshed = refreshed + 1 return real(...) end
    CH.Hub.spot.Save(320, 610)
    stub.RunTimers()
    CH.Chat.Refresh = real
    T.eq(refreshed, 0, "a drag doesn't repaint the chat")
    T.eq(db.spot[1], 320)
    for _, fn in ipairs(DaylightUI.Movers.onResetAll) do fn() end
    T.isnil(db.spot, "/dui reset forgets it")
    CH.Hub.Close()
    runMotion(1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: the watcher leaves the tiles alone when nothing about them changed", function()
    daylight()
    local CH = stub.chatModule
    whisper("hi", "Lephoque")
    runMotion(1)
    local real, n = CH.Tiles.Layout, 0
    CH.Tiles.Layout = function(...) n = n + 1 return real(...) end
    for _ = 1, 8 do CH.Tiles.Update(false) end
    CH.Tiles.Layout = real
    T.eq(n, 0, "no layout on a quiet pass")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The second panel (Box.lua): the tabs marked `side`, in their own chat box.

T.test("chat second panel: a tab moved over brings it up, and the last one back takes it away", function()
    local Box, box = daylight()
    local Tabs, side = stub.chatModule.Tabs, Box.side
    stub.RunTimers()
    T.falsy(Box.SideOn(), "nobody has one to start with")
    T.falsy(side.holder:IsShown())
    Box.Pick(4)   -- Loot, on the main panel
    T.truthy(Tabs.SetSide(4, true))
    stub.RunTimers()
    T.truthy(Box.SideOn() and side.holder:IsShown(), "up")
    T.eq(#Box.Tabs(), 4, "still one list")
    T.eq(side.picked, 4, "the tab shows there")
    T.eq(Box.Picked(), 1, "the main panel goes on to another tab")
    T.falsy(Box.main.buttons[4]:IsShown(), "its tab left the main row")
    T.truthy(side.buttons[4]:IsShown(), "and stands on the second")
    T.truthy(side.frame:IsShown() and box:IsShown(), "both lists showing")
    T.truthy(Tabs.SetSide(4, false))
    stub.RunTimers()
    T.falsy(Box.SideOn(), "the last tab back: gone")
    T.falsy(side.holder:IsShown())
    T.truthy(Box.main.buttons[4]:IsShown(), "back on the main row")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: each panel shows its own picked tab's lines", function()
    local Box, box = daylight()
    local Tabs, side = stub.chatModule.Tabs, Box.side
    Tabs.SetSide(4, true)
    Box.Pick(2)   -- Guild on the main panel, Loot on the second
    local function count(f) return f:GetNumMessages() end
    local mainBefore, sideBefore = count(box), count(side.frame)
    Box.Push({ "[Item]", 1, 1, 1, "loot" })
    T.eq(count(side.frame), sideBefore + 1, "loot lands on the second panel")
    T.eq(count(box), mainBefore, "not in Guild")
    Box.Push({ "hi", 1, 1, 1, "guild" })
    T.eq(count(box), mainBefore + 1, "guild lands on the main panel")
    T.eq(count(side.frame), sideBefore + 1)
    Box.Push({ "a note", 1, 1, 1, "*" })
    T.eq(count(box), mainBefore + 2, "a line for every tab shows on both")
    T.eq(count(side.frame), sideBefore + 2)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: another tab there counts its unread, picking it clears them", function()
    local Box = daylight()
    local Tabs, side = stub.chatModule.Tabs, Box.side
    Tabs.SetSide(3, true)
    Tabs.SetSide(4, true)
    Box.Pick(3)
    Box.Push({ "[Item]", 1, 1, 1, "loot" })
    T.eq(side.buttons[4].unread, 1)
    Box.Pick(4)
    T.eq(side.buttons[4].unread, 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: the corner panel always keeps a tab", function()
    local Box = daylight()
    local Tabs = stub.chatModule.Tabs
    for i = 1, 3 do T.truthy(Tabs.SetSide(i, true)) end
    T.falsy(Tabs.SetSide(4, true), "the last one stays")
    T.falsy(Box.Tabs()[4].side)
    Tabs.Remove(4)
    T.eq(#Box.Tabs(), 4, "and can't be removed either")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: a tab removed or moved keeps each panel on its tab", function()
    local Box = daylight()
    local Tabs, side = stub.chatModule.Tabs, Box.side
    Tabs.SetSide(4, true)
    Box.Pick(3)
    Tabs.Remove(1)
    T.eq(Box.Tabs()[side.picked].name, _G.LOOT or "Loot", "the second panel stays on Loot")
    T.eq(side.picked, 3, "at its new place")
    Tabs.MoveTo(3, 1)
    T.eq(side.picked, 1, "a move")
    T.truthy(side.buttons[1]:IsShown() and not side.buttons[3]:IsShown(), "its button by its new place")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: dragging a tab along its row and onto the other panel", function()
    local Box = daylight()
    local Tabs, side = stub.chatModule.Tabs, Box.side
    Tabs.SetSide(3, true)
    Tabs.SetSide(4, true)
    stub.RunTimers()
    Box.DragStart(3)
    Box.DragStop()
    T.truthy(Box.Tabs()[3].side, "let go on its own row: it stays")
    local over = Box.main.holder.IsMouseOver
    Box.main.holder.IsMouseOver = function() return true end
    Box.DragStart(3)
    Box.DragStop()
    Box.main.holder.IsMouseOver = over
    T.falsy(Box.Tabs()[3].side, "let go over the main panel: it moves there")
    T.eq(Box.Picked(), 3, "picked there")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: its combat log tab brings the game's window there", function()
    local selected
    local Box, box = daylight(function()
        _G.FCFDock_SelectWindow = function(_, cf) selected = cf end
    end)
    local CH = stub.chatModule
    local Tabs, side = CH.Tabs, Box.side
    Tabs.SetSide(4, true)
    local i = Tabs.Add(true, true)
    stub.RunTimers()
    Box.Pick(i)
    T.eq(selected, ChatFrame2, "selected in the dock")
    T.eq(ChatFrame2:GetAlpha(), 1, "seen")
    T.eq(select(2, ChatFrame2:GetPoint(1)), side.area, "in the second panel's place")
    T.falsy(side.frame:IsShown(), "that panel's list away")
    T.truthy(box:IsShown(), "the main panel's stays")
    Box.Pick(2)
    T.eq(selected, ChatFrame2, "picking on the main panel leaves it")
    T.eq(ChatFrame2:GetAlpha(), 1)
    ChatFrame2:ClearAllPoints()   -- the game anchors its docked windows again
    ChatFrame2:SetAllPoints(ChatFrame1)
    CH.Chat.Pass()
    T.eq(select(2, ChatFrame2:GetPoint(1)), side.area, "the watcher puts it back")
    T.truthy(Tabs.HasCombat(), "one log, one tab")
    Tabs.SetSide(i, false)
    stub.RunTimers()
    T.eq(select(2, ChatFrame2:GetPoint(1)), ChatFrame1, "with its tab: back on the main window's spot")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: a combat log tab removed lets the game's window go", function()
    local selected
    local Box = daylight(function()
        _G.FCFDock_SelectWindow = function(_, cf) selected = cf end
    end)
    local Tabs = stub.chatModule.Tabs
    Tabs.SetSide(4, true)
    local i = Tabs.Add(true, true)
    Box.Pick(i)
    Tabs.Remove(i)
    T.eq(selected, ChatFrame1)
    T.eq(ChatFrame2:GetAlpha(), 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: the options' switch, and Classic", function()
    local Box = daylight()
    local Tabs, side = stub.chatModule.Tabs, Box.side
    local DUI = DaylightUI
    Tabs.ShowSide(true)
    stub.RunTimers()
    T.truthy(Box.Tabs()[4].side, "the Loot tab goes over")
    T.truthy(Box.SideOn())
    Tabs.ShowSide(false)
    stub.RunTimers()
    T.falsy(Tabs.SideShown(), "every tab back")
    Tabs.Remove(4)
    Tabs.ShowSide(true)
    stub.RunTimers()
    T.eq(#Box.Tabs(), 4, "no Loot tab: a new one")
    T.truthy(Box.Tabs()[4].side)
    DUI:Set("Chat", "style", "classic")
    stub.RunTimers()
    T.falsy(side.holder:IsShown(), "Classic has the game's own windows to pull out")
    DUI:Set("Chat", "style", "daylight")
    stub.RunTimers()
    T.truthy(side.holder:IsShown(), "back with its tabs")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: it has its own size, and fades and floats with the chat", function()
    local Box = daylight()
    local CH = stub.chatModule
    local Tabs, side = CH.Tabs, Box.side
    local DUI = DaylightUI
    Tabs.SetSide(4, true)
    stub.RunTimers()
    DUI:Set("Chat", "sideWidth", 400)
    DUI:Set("Chat", "sideHeight", 300)
    local both = 2 * CH.Chat.inset
    T.eq(side.holder:GetWidth(), 400 + both)
    T.eq(side.holder:GetHeight(), 300 + both)
    T.falsy(DUI:Get("Chat", "width") == 400, "the main panel's stays its own")
    DUI:Set("Chat", "hides", "always")
    function DaylightUIChat:IsMouseOver() return false end
    function DaylightUIChatSide:IsMouseOver() return false end
    CH.Chat.awakeUntil, CH.Chat.sideAwakeUntil = 0, 0
    CH.Chat.UpdateFade()
    runMotion(1)
    T.eq(side.panel:GetAlpha(), 0, "floating: its panel goes too")
    T.truthy(side.frame:IsShown(), "and the lines stay")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: its own Second panel hides pick floats it apart from the main chat", function()
    local Box = daylight()
    local CH = stub.chatModule
    local side = Box.side
    local DUI = DaylightUI
    CH.Tabs.SetSide(4, true)
    stub.RunTimers()
    function DaylightUIChat:IsMouseOver() return false end
    function DaylightUIChatSide:IsMouseOver() return false end
    local function settle()
        CH.Chat.awakeUntil, CH.Chat.sideAwakeUntil = 0, 0
        CH.Chat.UpdateFade()
        runMotion(1)
    end
    DUI:Set("Chat", "hides", "never")
    DUI:Set("Chat", "sideHides", "always")
    settle()
    T.eq(side.panel:GetAlpha(), 0, "the second panel floats by its own pick")
    T.eq(CH.Chat.Panel():GetAlpha(), 1, "the main chat stays")
    T.falsy(CH.Chat.FloatWanted(), "the main chat isn't asked to float")
    DUI:Set("Chat", "hides", "always")
    DUI:Set("Chat", "sideHides", "never")
    settle()
    T.eq(CH.Chat.Panel():GetAlpha(), 0, "the other way round: the main chat floats")
    T.eq(side.panel:GetAlpha(), 1, "and the second panel stays up")
    function DaylightUIChatSide:IsMouseOver() return true end
    DUI:Set("Chat", "sideHides", "always")
    settle()
    T.eq(side.panel:GetAlpha(), 1, "the mouse over it brings it back")
    T.eq(CH.Chat.Panel():GetAlpha(), 0, "and only it")
    function DaylightUIChatSide:IsMouseOver() return false end
    DUI:Set("Chat", "sideHides", "chat")
    settle()
    T.eq(side.panel:GetAlpha(), 0, "As the main chat: it goes with it again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: the mouse over one panel never brings the other back", function()
    local Box = daylight()
    local CH = stub.chatModule
    local side = Box.side
    local DUI = DaylightUI
    CH.Tabs.SetSide(4, true)
    stub.RunTimers()
    DUI:Set("Chat", "hides", "always")
    DUI:Set("Chat", "sideHides", "chat")
    local function settle(main, second)
        function DaylightUIChat:IsMouseOver() return main end
        function DaylightUIChatSide:IsMouseOver() return second end
        CH.Chat.awakeUntil, CH.Chat.sideAwakeUntil = 0, 0
        CH.Chat.UpdateFade()
        runMotion(1)
    end
    settle(true, false)
    T.eq(CH.Chat.Panel():GetAlpha(), 1, "the main chat comes back under the mouse")
    T.eq(side.panel:GetAlpha(), 0, "the second panel stays away")
    settle(false, true)
    T.eq(side.panel:GetAlpha(), 1, "the second panel comes back under the mouse")
    T.eq(CH.Chat.Panel():GetAlpha(), 0, "the main chat stays away")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: with its own idle pick it fades on its own clock", function()
    local Box = daylight()
    local CH = stub.chatModule
    local DUI = DaylightUI
    CH.Tabs.SetSide(4, true)
    stub.RunTimers()
    DUI:Set("Chat", "hides", "never")
    DUI:Set("Chat", "sideHides", "fightsIdle")
    DUI:Set("Chat", "idleAfter", 3)
    function DaylightUIChat:IsMouseOver() return false end
    function DaylightUIChatSide:IsMouseOver() return false end
    local function settle()
        CH.Chat.UpdateFade()
        DUI.Fade.Step()
        for _ = 1, 120 do stub.RunOnUpdate(DUI.Fade.driver, 1 / 60) end
    end
    settle()
    stub.Advance(5)
    settle()
    T.eq(Box.side.holder:GetAlpha(), 0, "idle, the second panel fades")
    T.eq(DaylightUIChat:GetAlpha(), 1, "the main chat, set to never, stays")
    function DaylightUIChatSide:IsMouseOver() return true end
    settle()
    T.eq(Box.side.holder:GetAlpha(), 1, "the mouse over it brings it back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: with Chat hides Always it stays seen a moment after it arrives, then floats", function()
    local Box = daylight()
    local CH = stub.chatModule
    local side = Box.side
    DaylightUI:Set("Chat", "hides", "always")
    function DaylightUIChat:IsMouseOver() return false end
    function DaylightUIChatSide:IsMouseOver() return false end
    CH.Chat.UpdateFade()
    runMotion(1)
    T.eq(CH.Chat.Panel():GetAlpha(), 0, "floating, the mouse elsewhere (in the menu or the options)")
    CH.Tabs.SetSide(4, true)
    CH.Chat.UpdateFade()
    runMotion(1)
    T.eq(side.panel:GetAlpha(), 1, "you see where it landed")
    CH.Chat.awakeUntil, CH.Chat.sideAwakeUntil = 0, 0
    CH.Chat.UpdateFade()
    runMotion(1)
    T.eq(side.panel:GetAlpha(), 0, "then it floats as the chat does")
    DaylightUI:Set("Chat", "lineTime", 9)
    T.eq(CH.Chat.sideAwakeUntil, 0, "a setting changed later doesn't bring it back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: it arrives by a stepped fade, never an alpha animation that could leave it clear", function()
    local Box = daylight()
    local CH = stub.chatModule
    local body = Box.side.body
    CH.Tabs.ShowSide(true)
    stub.RunTimers()
    for _, g in pairs(body.__duiMotion or {}) do
        T.falsy(g.__alpha and g:IsPlaying(), "an alpha animation on the panel (seen in game: a blip, then gone)")
    end
    runMotion(1)
    T.eq(body:GetAlpha(), 1, "eased in")
    CH.Tabs.ShowSide(false)
    stub.RunTimers()
    runMotion(1)
    T.falsy(Box.side.holder:IsShown(), "and away with its last tab")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: after a reload it's simply there, with no ease-in during the loading screen", function()
    local Box = daylight(function()
        _G.DaylightUIDB = { modules = { Chat = { tabs = {
            { name = "General", all = true, v = 2 },
            { name = "Trade", kinds = { trade = true }, side = true, v = 2 },
        } } } }
    end)
    local side = Box.side
    T.truthy(Box.SideOn() and side.holder:IsShown(), "up from the start")
    T.eq(side.body.__duiMotion, nil, "no slide-in: an animation started while the game loads can stay stuck at clear")
    T.eq(side.body:GetAlpha(), 1, "and no fade")
    T.eq(stub.chatModule.Chat.sideAwakeUntil, 0, "nor held awake")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat panels: unlocked, a drag on the bare tab row moves the panel and saves its spot", function()
    local Box = daylight()
    local CH = stub.chatModule
    local side = Box.side
    CH.Tabs.SetSide(4, true)
    stub.RunTimers()
    local save, saved = DaylightUI.Movers.Save, nil
    DaylightUI.Movers.Save = function(key, ...) saved = key return save(key, ...) end
    local strip = side.strip
    strip:GetScript("OnDragStart")(strip)
    T.truthy(side.holder.__moving, "it follows the mouse")
    T.truthy(CH.Chat.sideSizing, "and stays seen while it does")
    strip:GetScript("OnDragStop")(strip)
    T.falsy(side.holder.__moving)
    T.eq(saved, "chat.side", "the spot kept")
    T.falsy(CH.Chat.sideSizing)
    saved = nil
    local mainStrip = Box.main.strip
    mainStrip:GetScript("OnDragStart")(mainStrip)
    T.truthy(DaylightUIChat.__moving, "the main panel too")
    mainStrip:GetScript("OnDragStop")(mainStrip)
    T.eq(saved, "chat")
    saved = nil
    DaylightUI:Set("Chat", "locked", true)
    strip:GetScript("OnDragStart")(strip)
    strip:GetScript("OnDragStop")(strip)
    T.falsy(side.holder.__moving, "the padlock closed: it stays")
    T.eq(saved, nil)
    DaylightUI:Set("Chat", "locked", false)
    local fight = _G.InCombatLockdown
    _G.InCombatLockdown = function() return true end
    strip:GetScript("OnDragStart")(strip)
    _G.InCombatLockdown = fight
    T.falsy(side.holder.__moving, "not in a fight")
    DaylightUI.Movers.Save = save
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat panels: with more tabs than fit, a drag on the row still slides the tabs", function()
    local Box = daylight()
    local main = Box.main
    for _ = 1, 6 do stub.chatModule.Tabs.Add(false) end
    Box.LayoutTabs()
    main.strip.GetWidth = function() return 120 end
    Box.LayoutTabs()
    main.strip:GetScript("OnDragStart")(main.strip)
    T.falsy(DaylightUIChat.__moving, "the tabs slide, the chat stays")
    main.strip:GetScript("OnDragStop")(main.strip)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- The panels' border, the second panel's opacity, and the text sizes of the tabs
-- and input
-- ---------------------------------------------------------------------

T.test("chat border: As the chat style, then each style on every panel", function()
    local Box = daylight()
    local DUI, Style = DaylightUI, DaylightUI.Style
    stub.chatModule.Tabs.ShowSide(true)
    stub.RunTimers()
    local main, side = Style.GetShell(DaylightUIChatPanel), Style.GetShell(Box.side.panel)
    local float
    for _, c in ipairs({ ChatFrame3:GetChildren() }) do
        if Style.GetShell(c) then float = Style.GetShell(c) end
    end
    T.falsy(main.opts.flat, "the Daylight box: the Daylight frame")
    T.falsy(side.opts.flat, "the second panel too")
    T.falsy(float.opts.flat, "and a window out of the dock")
    DUI:Set("Chat", "border", "flat")
    DUI:Set("Chat", "borderSize", 3)
    stub.RunTimers()
    for name, s in pairs({ main = main, side = side, float = float }) do
        T.truthy(s.opts.flat, name .. ": flat")
        T.eq(s.opts.borderPx, 3, name .. ": its thickness")
    end
    DUI:Set("Chat", "border", "none")
    stub.RunTimers()
    T.truthy(main.opts.noBorder, "None: no border")
    T.truthy(side.opts.noBorder)
    DUI:Set("Chat", "border", "auto")
    DUI:Set("Chat", "style", "classic")
    stub.RunTimers()
    T.truthy(main.opts.flat, "Classic: its thin line")
    T.eq(main.opts.borderPx, 3, "the Flat thickness")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat border: its color on every panel, kept after the grip's light", function()
    local Box = daylight()
    local DUI, Style = DaylightUI, DaylightUI.Style
    stub.chatModule.Tabs.ShowSide(true)
    stub.RunTimers()
    local main, side = Style.GetShell(DaylightUIChatPanel), Style.GetShell(Box.side.panel)
    T.eq(main.opts.borderColor, nil, "Default: the shell's own")
    DUI:Set("Chat", "borderColor", "custom")
    DUI:Set("Chat", "borderCustom", { 0.2, 0.4, 0.6 })
    stub.RunTimers()
    T.eq(main.opts.borderColor[3], 0.6, "your own color")
    T.eq(side.opts.borderColor[3], 0.6, "on the second panel too")
    T.near(main.opts.bandColor[3], 0.6 * stub.chatModule.Chat.BAND_K, 0.001, "the Daylight band a darker one")
    stub.chatModule.Feel.Sizing(true)
    stub.RunTimers()
    stub.chatModule.Feel.Sizing(false)
    stub.RunTimers()
    T.eq(main.opts.borderColor[3], 0.6, "back to it after sizing")
    DUI:Set("Chat", "borderColor", "accent")
    stub.RunTimers()
    local r, g, b = Style.Accent()
    T.eq(main.opts.borderColor[1], r, "the accent")
    DUI:Set("Chat", "borderColor", "shell")
    stub.RunTimers()
    T.eq(main.opts.borderColor, nil, "Default again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: a background opacity of its own, else the main panel's", function()
    local Box = daylight()
    local DUI, Style = DaylightUI, DaylightUI.Style
    stub.chatModule.Tabs.ShowSide(true)
    DUI:Set("Chat", "panelAlphaOwn", true)
    DUI:Set("Chat", "panelAlpha", 0.6)
    stub.RunTimers()
    local side = Style.GetShell(Box.side.panel)
    T.eq(side.opts.bgAlpha, 0.6, "the main panel's")
    DUI:Set("Chat", "sideAlphaOwn", true)
    DUI:Set("Chat", "sideAlpha", 0.3)
    stub.RunTimers()
    T.eq(side.opts.bgAlpha, 0.3, "its own")
    T.eq(Style.GetShell(DaylightUIChatPanel).opts.bgAlpha, 0.6, "the main one keeps its")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: a text size of its own, else the main chat's", function()
    local Box = daylight()
    local DUI = DaylightUI
    stub.chatModule.Tabs.ShowSide(true)
    DUI:Set("Chat", "textSize", 15)
    stub.RunTimers()
    T.eq(select(2, Box.side.frame:GetFont()), 15, "the main chat's")
    DUI:Set("Chat", "sideTextSizeOwn", true)
    DUI:Set("Chat", "sideTextSize", 11)
    stub.RunTimers()
    T.eq(select(2, Box.side.frame:GetFont()), 11, "its own")
    T.eq(select(2, Box.main.frame:GetFont()), 15, "the main one keeps its")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat text: the tabs' size, and the input box's own", function()
    local Box = daylight()
    local DUI = DaylightUI
    DUI:Set("Chat", "textSize", 16)
    DUI:Set("Chat", "tabSize", 16)
    stub.RunTimers()
    local b = Box.main.buttons[1]
    T.eq(select(2, b.text:GetFont()), 16, "a tab's words")
    T.eq(select(2, ChatFrame1EditBox:GetFont()), 16, "the box follows the messages")
    DUI:Set("Chat", "inputSizeOwn", true)
    DUI:Set("Chat", "inputSize", 20)
    stub.RunTimers()
    T.eq(select(2, ChatFrame1EditBox:GetFont()), 20, "its own size")
    T.eq(select(2, ChatFrame1:GetFont()), 16, "the messages keep theirs")
    DUI:Set("Chat", "style", "classic")
    stub.RunTimers()
    T.eq(select(2, ChatFrame2Tab.Text:GetFont()), 16, "Classic: the game's tab words too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat whispers: an unread tile breathes in the whisper's color until it's read, then its light eases away", function()
    daylight(function()
        _G.ChatTypeInfo = _G.ChatTypeInfo or {}
        _G.ChatTypeInfo.WHISPER = { r = 1, g = 0.5, b = 1, id = 7 }
    end)
    local CH = stub.chatModule
    whisper("you there?", "Lephoque")
    local tile = shownTiles()[1]
    local shell = DaylightUI.Style.GetShell(tile)
    T.eq(shell.opts.borderColor and shell.opts.borderColor[2], 0.5, "the border in the whisper's color")
    local seen = {}
    for i = 1, 24 do
        CH.Feel.Step(0.1)
        seen[#seen + 1] = tile.glow:GetAlpha()
    end
    local lo, hi = math.min(unpack(seen)), math.max(unpack(seen))
    T.truthy(hi > 0.3, "its light comes up: " .. hi)
    T.truthy(hi - lo > 0.15, "and breathes, not a still light")
    T.eq(select(2, tile.glow:GetVertexColor()), 0.5, "in the whisper's color")
    tile:GetScript("OnClick")(tile, "LeftButton")
    T.eq(CH.Talk.Get("w:Lephoque").unread, 0, "read")
    CH.Feel.Step(0.1)
    T.truthy(tile.glow:GetAlpha() > 0, "it doesn't vanish in one frame")
    runMotion(0.5)
    T.eq(tile.glow:GetAlpha(), 0, "eased away")
    T.falsy(DaylightUI.Style.GetShell(tile).opts.borderColor
        and DaylightUI.Style.GetShell(tile).opts.borderColor[2] == 0.5, "the border back from the whisper's color")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: tradeskills, currency, battlegrounds and the game's other chat settings are kinds of their own", function()
    local Box = daylight()
    local Kinds = stub.chatModule.Kinds
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_TRADESKILLS")), "tradeskill")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_OPENING")), "opening")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_CURRENCY")), "currency")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_BG_SYSTEM_HORDE")), "pvp")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_TARGETICONS")), "icons")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_BN_INLINE_TOAST_ALERT")), "bnalert")
    for _, kind in ipairs(Kinds.ORDER) do
        T.truthy(stub.chatModule.Tabs.KIND_WORDS[kind], "words for " .. kind)
    end
    DaylightUI:Set("Chat", "tabs", { { name = "Old", v = 5, kinds = { loot = true, money = true } },
                                     { name = "Sys", v = 5, kinds = { system = true } } })
    stub.RunTimers()
    local loot, sys = Box.Tabs()[1], Box.Tabs()[2]
    T.truthy(loot.kinds.tradeskill and loot.kinds.opening and loot.kinds.currency, "loot and money brought theirs along")
    T.falsy(loot.kinds.pvp, "nothing it didn't show")
    T.truthy(sys.kinds.pvp and sys.kinds.pet and sys.kinds.misc and sys.kinds.icons and sys.kinds.bnalert,
        "what went to System still shows there")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a tab's right-click menu opens its switches under Channels", function()
    daylight()
    local Tabs = stub.chatModule.Tabs
    local seen
    local open = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, keys, values) seen = values end
    Tabs.OpenMenu(UIParent, 1)
    DaylightUI.Widgets.OpenMenu = open
    T.eq(seen and seen.show, "Channels")
end)
