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
    -- The template's button over the whole window: in the IM chat style a click on it
    -- makes this window's box the one you type in (FloatingChatFrameClickAnywhereButtonMixin).
    cf.clickAnywhereButton = CreateFrame("Button", name .. "ClickAnywhereButton", cf)
    cf.clickAnywhereButton:EnableMouse(true)
    for _, e in ipairs(SHOWN) do cf:RegisterEvent(e) end
    -- Its message groups, read by the game's ChatFrameMixin:ContainsMessageGroup.
    cf.messageTypeList = {}
    for _, e in ipairs(SHOWN) do cf.messageTypeList[#cf.messageTypeList + 1] = e:sub(10) end
    function cf:ContainsMessageGroup(group)
        for _, g in pairs(self.messageTypeList) do if g == group then return true end end
        return false
    end
    cf.channelList, cf.zoneChannelList = {}, {}
    -- Its lines as the window keeps them, added and rewritten in place. Each is
    -- also the game's history entry (PackageEntry): `message` is [1], the values
    -- after r, g, b are in `extraData` (the event is 4th), and the arrival time
    -- is in `timestamp`.
    cf.lines = {}
    function cf:AddMessage(msg, r, g, b, ...)
        local extra = { n = select("#", ...), ... }
        table.insert(self.lines, { msg, extra[4], r, g, b, timestamp = GetTime(), extra = extra })
    end
    function cf:GetNumMessages() return #self.lines end
    -- As the game's UnpackageEntry: message, r, g, b, then AddMessage's extra values.
    function cf:GetMessageInfo(i)
        local l = self.lines[i]
        if not l then return end
        if l.extra then return l[1], l[3], l[4], l[5], unpack(l.extra, 1, l.extra.n) end
        return l[1], l[3], l[4], l[5]
    end
    -- The game's TransformMessages: picked entries rewritten in place, no AddMessage.
    function cf:TransformMessages(pred, fn)
        for _, l in ipairs(self.lines) do
            local x = l.extra or { n = 0 }
            if pred(l[1], l[3], l[4], l[5], unpack(x, 1, x.n)) then
                local out = (function(...) return { n = select("#", ...), ... } end)(fn(l[1], l[3], l[4], l[5], unpack(x, 1, x.n)))
                l[1], l[3], l[4], l[5] = out[1], out[2], out[3], out[4]
                l.extra = { n = math.max(out.n - 4, 0), unpack(out, 5, out.n) }
                l.timestamp = GetTime()
            end
        end
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

-- The game's Chat Style (Options, Social) is the player's own pick: it was set to
-- IM at every login, so a player who chose Classic lost it, with Daylight UI's
-- chat switched off too.
T.test("chat: the game's chat style stays the one the player picked", function()
    for _, style in ipairs({ "classic", "daylight" }) do
        for _, pick in ipairs({ "classic", "im" }) do
            login(function()
                stub.cvars.chatStyle = pick
                if style == "daylight" then
                    _G.ChatTypeInfo = { SYSTEM = { id = 1, r = 1, g = 1, b = 0 }, SAY = { id = 4, r = 1, g = 1, b = 1 } }
                end
            end, style)
            DaylightUI:Set("Chat", "classColors", false)
            stub.RunTimers()
            T.eq(stub.cvars.chatStyle, pick, style .. " chat box, " .. pick .. " picked: left as it is")
        end
    end
    -- Classic style types in ChatFrame1's box only, which the game hides when
    -- you're done: it still lands where the chat types.
    login(function() stub.cvars.chatStyle = "classic" end, "daylight")
    stub.chatModule.Chat.Pass()
    T.eq(select(2, ChatFrame1EditBox:GetPoint(1)), stub.chatModule.Box.Field(), "in the footer")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: whispers show their time in the Timestamps format", function()
    login()
    local Chat = stub.chatModule.Chat
    local at = os.time({ year = 2026, month = 10, day = 5, hour = 21, min = 19 })
    DaylightUI:Set("Chat", "timestamps", "%I:%M %p ")
    stub.RunTimers()
    T.eq(Chat.Clock(at), "09:19 PM", "a 12-hour clock, no trailing space")
    DaylightUI:Set("Chat", "timestamps", "none")
    stub.RunTimers()
    T.eq(Chat.Clock(at), "21:19", "timestamps off: hours and minutes")
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
    T.eq(_G.DaylightUIChatDrawer:GetFrameStrata(), "HIGH", "its clipping drawer too, since a clipping frame draws its children in its own strata")
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
    DaylightUI:Set("Chat", "frameStyle.windowAlpha", 0.4)
    stub.RunTimers()
    T.eq(DaylightUI.Style.GetShell(panel).opts.bgAlpha, 0.6, "its own only off the global style")
    DaylightUI:Set("Chat", "frameStyle.global", false)
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

-- A repaint also comes from a screen or UI scale change. With nothing about
-- the chat changed, the game's chat window and edit box keep their anchors.
T.test("chat: a repaint that changed nothing leaves the game's chat window anchors alone", function()
    local DUI = login()
    stub.RunTimers()
    local clears = 0
    for _, f in ipairs({ ChatFrame1, ChatFrame1EditBox }) do
        local real = f.ClearAllPoints
        f.ClearAllPoints = function(...) clears = clears + 1 return real(...) end
    end
    DUI.NotifyStyleChanged()
    stub.RunTimers()
    T.eq(clears, 0, "nothing placed again")
    DUI:Set("Chat", "inputAt", "below"); DUI:Set("Chat", "boxInputAt", "top")
    stub.RunTimers()
    T.truthy(clears > 0, "a real change still moves the box")
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

-- A speech bubble as the game hands it out: an empty holder whose one child
-- draws the balloon and carries the text (its String key, as in the game).
local function makeBubble(text)
    local outer = CreateFrame("Frame", nil, UIParent)
    local art = CreateFrame("Frame", nil, outer)
    local tex = art:CreateTexture()
    tex:SetTexture("bubble art")
    local fs = art:CreateFontString()
    fs:SetFont("GameFont", 12, "")
    fs:SetText(text or "Hello there")
    fs:SetTextColor(1, 1, 0.5)
    art.String = fs
    return outer, art, tex, fs
end

T.test("chat: a speech bubble is drawn by a frame of Daylight UI's own, the game's frame is only faded", function()
    login()
    local Bubbles = stub.chatModule.Bubbles
    local b1, art, tex, fs = makeBubble("Hello there")
    local b2 = CreateFrame("Frame", nil, UIParent)
    b2.__forbidden = true
    stub.SetBubbles({ b1, b2 })
    -- The client refuses text on a font string with no font yet.
    stub.FontRule = true
    local errs, last = 0, nil
    local onError = DaylightUI.SafeCall
    DaylightUI.SafeCall = function(fn, ...)
        local ok, e = pcall(fn, ...)
        if not ok then errs, last = errs + 1, e end
    end
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    DaylightUI.SafeCall, stub.FontRule = onError, nil
    T.eq(errs, 0, "no error drawing a new bubble: " .. tostring(last))
    local mine = Bubbles.OverlayOf(b1)
    T.truthy(mine, "drawn")
    T.eq(mine:GetParent(), UIParent, "on UIParent, outside the world layer")
    T.truthy(mine:IsShown(), "shown")
    T.eq(mine.text:GetText(), "Hello there", "the bubble's own words")
    T.eq(mine.text:GetFont(), DaylightUI.Style.FONT, "Daylight font")
    T.truthy(DaylightUI.Style.GetShell(mine), "Daylight frame")
    T.eq(art:GetAlpha(), 0, "the game's balloon faded out")
    T.eq(tex.__texture, "bubble art", "its art left as it is")
    T.eq(fs:GetFont(), "GameFont", "its text left as it is")
    T.isnil(DaylightUI.Style.GetShell(art), "nothing built on the game's frame")
    T.eq(select(2, mine:GetPoint(1)), art, "follows the balloon")
    T.isnil(Bubbles.OverlayOf(b2), "forbidden (an instance): left alone")
end)

T.test("chat: a speech bubble has square corners with the bottom-right one cut, an accent band and a tail", function()
    login()
    local Style = DaylightUI.Style
    local Bubbles = stub.chatModule.Bubbles
    local outer = makeBubble("Anyone for Deadmines?")
    stub.SetBubbles({ outer })
    Bubbles.DressAll()
    local mine = Bubbles.OverlayOf(outer)
    T.truthy(Style.GetCut(mine) > 0, "the corner cut")
    T.isnil(Style.GetSlant(mine), "no angled ends")
    T.truthy(mine.band and mine.band:IsShown(), "an accent band along the bottom")
    T.eq(select(1, mine.band:GetPoint(1)), "BOTTOMLEFT", "at the bottom")
    T.truthy(mine.band:GetNumMaskTextures() > 0, "the band cut with the corner")
    T.truthy(mine.tail and mine.tail:IsShown(), "a tail")
    T.eq(select(3, mine.tail:GetPoint(1)), "BOTTOMLEFT", "hung under the bubble")
end)

-- The tail's tip is where the tail's left edge meets the bubble's bottom.
local function tailTip(mine)
    local _, rel, relPoint, x = mine.tail:GetPoint(1)
    assert(rel == mine and relPoint == "BOTTOMLEFT")
    return x
end

T.test("chat: a long bubble's tail still points at the speaker, where the game's own tail is", function()
    login()
    local Bubbles = stub.chatModule.Bubbles
    -- A whole sentence, wide enough to wrap: the old tail sat a sixth of the
    -- way along and slid far left of the speaker's head.
    local long = string.rep("i made the jump hugeeeee ", 6)
    local outer, art = makeBubble(long)
    art.__center = { 500, 300 }
    -- The game's tail sits under the speaker, here 10 px left of the balloon's middle.
    art.Tail = art:CreateTexture()
    art.Tail.__center = { 490, 270 }
    stub.SetBubbles({ outer })
    Bubbles.DressAll()
    local mine = Bubbles.OverlayOf(outer)
    local w = mine:GetWidth()
    T.truthy(w > 200, "a wide bubble: " .. tostring(w))
    T.near(tailTip(mine), w / 2 - 10, 1, "the tip under the game's tail")
    -- A few words: the tip still follows the game's tail.
    local outer2, art2 = makeBubble("i made the jump")
    art2.__center = { 500, 300 }
    art2.Tail = art2:CreateTexture()
    art2.Tail.__center = { 500, 270 }
    stub.SetBubbles({ outer2 })
    Bubbles.DressAll()
    local small = Bubbles.OverlayOf(outer2)
    T.near(tailTip(small), small:GetWidth() / 2, 1, "short: under the middle")
    -- No game tail to read (or a secret one): the balloon sits centered over
    -- the speaker, so the tip goes to the middle.
    local outer3 = makeBubble(long)
    stub.SetBubbles({ outer3 })
    Bubbles.DressAll()
    local plain = Bubbles.OverlayOf(outer3)
    T.near(tailTip(plain), plain:GetWidth() / 2, 1, "no game tail: the middle")
end)

T.test("chat: a bubble's line can wear its speaker's class; the tail stays dark with colored edges", function()
    login()
    local Style = DaylightUI.Style
    local Bubbles = stub.chatModule.Bubbles
    stub.units.party1 = { name = "Jaina", class = "MAGE", guid = "Player-1-0000JAIN", isPlayer = true }
    DaylightUI:Set("Chat", "bubbleColor", "class")
    local said = makeBubble("Anyone for Deadmines?")
    local npc = makeBubble("You no take candle!")
    local locked = makeBubble("Hush now")
    stub.SetBubbles({ said, npc, locked })
    stub.FireEvent("CHAT_MSG_SAY", "Anyone for Deadmines?", "Jaina", "", "", "", "", 0, 0, "", 0, 1, "Player-1-0000JAIN")
    stub.FireEvent("CHAT_MSG_MONSTER_SAY", "You no take candle!", "Kobold", "", "", "", "", 0, 0, "", 0, 2, "Creature-0-1")
    -- Chat lockdown: the line and its sender come as secrets.
    stub.FireEvent("CHAT_MSG_SAY", stub.Secret("Hush now"), "Jaina", "", "", "", "", 0, 0, "", 0, 3, stub.Secret("Player-1-0000JAIN"))
    stub.RunTimers()
    local mine, theirs, hushed = Bubbles.OverlayOf(said), Bubbles.OverlayOf(npc), Bubbles.OverlayOf(locked)
    local lo, hi = DaylightUI.Gradients.RGB("MAGE")
    local g = mine.band.__gradient
    T.truthy(g, "a gradient line")
    T.near(g[3].r, hi[1], 0.01, "the mage pair's light end")
    T.isnil(theirs.class, "an NPC has no class")
    T.isnil(hushed.class, "a secret line teaches nothing")
    local accentHi = select(2, Style.AccentPair())
    if accentHi then T.near(theirs.band.__gradient[3].r, accentHi[1], 0.01, "the NPC keeps the accent") end
    -- The tail: the bubble's dark, with the line's color only on its edges.
    local bg = Style.BACKGROUND
    T.near(select(1, mine.tail.tex:GetVertexColor()), bg[1], 0.01, "the tail is dark")
    T.truthy(mine.tail.side:IsShown() and mine.tail.slope:IsShown(), "edged")
    local t = Bubbles.TAIL_AT
    T.near(mine.tail.side.__color[1], lo[1] + (hi[1] - lo[1]) * t, 0.2, "its edges in the mage colors")
    DaylightUI:Set("Chat", "bubbleColor", "accent")
end)

T.test("chat: the bubble options take the accent line away, square the corner and thin the background", function()
    login()
    local Style = DaylightUI.Style
    local Bubbles = stub.chatModule.Bubbles
    local outer = makeBubble("Anyone for Deadmines?")
    stub.SetBubbles({ outer })
    Bubbles.DressAll()
    local mine = Bubbles.OverlayOf(outer)
    local h = mine:GetHeight()
    DaylightUI:Set("Chat", "bubbleBand", 0)
    DaylightUI:Set("Chat", "bubbleCut", false)
    DaylightUI:Set("Chat", "bubbleAlpha", 0.5)
    stub.RunTimers()
    T.falsy(mine.band:IsShown(), "no accent line")
    T.truthy(mine:GetHeight() < h, "the bubble shrinks by the line")
    T.eq(Style.GetCut(mine), 0, "four square corners")
    T.eq(Style.GetShell(mine).opts.bgAlpha, 0.5, "the background as set")
    T.truthy(mine.tail:IsShown(), "the tail stays")
    DaylightUI:Set("Chat", "bubbleBand", 6)
    DaylightUI:Set("Chat", "bubbleCut", true)
    stub.RunTimers()
    T.truthy(mine.band:IsShown(), "the line back")
    T.truthy(Style.GetCut(mine) > 0, "cut again")
end)

T.test("chat: a zero unbounded width falls back to the measured speech line", function()
    login()
    local Bubbles = stub.chatModule.Bubbles
    local outer, art = makeBubble("Fresh words")
    stub.SetBubbles({ outer })
    Bubbles.DressAll()
    local mine = Bubbles.OverlayOf(outer)
    mine.text.GetUnboundedStringWidth = function() return 0 end
    mine.text.GetStringWidth = function() return 52.5 end
    Bubbles.Refresh()
    T.eq(mine.text:GetWidth(), 54, "fits the bounded measurement")
    T.eq(art:GetAlpha(), 0, "the stand-in shows the words")
end)

T.test("chat: unreadable speech measurements hand the words back to the game", function()
    login()
    local Bubbles = stub.chatModule.Bubbles
    local outer, art = makeBubble("Fresh words")
    stub.SetBubbles({ outer })
    Bubbles.DressAll()
    local mine = Bubbles.OverlayOf(outer)
    mine.text.GetUnboundedStringWidth = function() return 0 end
    mine.text.GetStringWidth = function() return stub.Secret(48) end
    Bubbles.Refresh()
    T.eq(art:GetAlpha(), 1, "the game draws the words")
    T.falsy(mine:IsShown(), "no one-unit-wide stand-in")
    mine.text.GetStringWidth = function() return 48 end
    mine.text.GetStringHeight = function() error("refused") end
    Bubbles.DressAll()
    T.eq(art:GetAlpha(), 1, "a refused height leaves it to the game")
    mine.text.GetStringHeight = function() return 12 end
    Bubbles.DressAll()
    T.truthy(mine:IsShown(), "the same line is taken again")
    T.eq(mine.text:GetWidth(), 49)
    T.eq(art:GetAlpha(), 0)
end)

T.test("chat: a pooled balloon that moves to another bubble stays with its new owner", function()
    login()
    local Bubbles = stub.chatModule.Bubbles
    local b1, art = makeBubble("First")
    stub.SetBubbles({ b1 })
    Bubbles.DressAll()
    T.eq(art:GetAlpha(), 0)
    -- The client hands the balloon to another holder, and b1 a fresh one.
    local b2 = CreateFrame("Frame", nil, UIParent)
    art:SetParent(b2)
    stub.SetBubbles({ b2 })
    Bubbles.DressAll()
    T.eq(select(2, Bubbles.OverlayOf(b2):GetPoint(1)), art, "drawn by its new holder")
    -- The old holder only hears about it afterwards.
    b1:Hide()
    stub.RunTimers()
    T.eq(art:GetAlpha(), 0, "the old holder leaves the moved balloon alone")
    -- A fresh balloon with the same words still gets the stand-in pinned to it.
    local _, art2 = makeBubble("First")
    art2:SetParent(b2)
    art:SetParent(UIParent)
    stub.SetBubbles({ b2 })
    Bubbles.DressAll()
    T.eq(select(2, Bubbles.OverlayOf(b2):GetPoint(1)), art2, "re-pinned to the new balloon")
    T.eq(art2:GetAlpha(), 0)
end)

T.test("chat: a bubble that goes out of sight takes its look along and gets it back", function()
    login()
    local Bubbles = stub.chatModule.Bubbles
    local b1, art = makeBubble("Over here")
    stub.SetBubbles({ b1 })
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    b1:Hide()
    stub.Advance(1)
    stub.RunTimers()
    T.falsy(Bubbles.OverlayOf(b1):IsShown(), "gone with it")
    T.eq(art:GetAlpha(), 1, "the game's frame handed back")
    b1:Show()
    stub.RunTimers()
    T.truthy(Bubbles.OverlayOf(b1):IsShown(), "back with it")
    T.eq(art:GetAlpha(), 0)
    art.String:SetText("Something new")
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    T.eq(Bubbles.OverlayOf(b1).text:GetText(), "Something new", "a new line in the same bubble")
end)

T.test("chat: a bubble's stand-in lets go of the game's frame as it goes", function()
    login()
    local Bubbles = stub.chatModule.Bubbles
    local b1, art = makeBubble("Over here")
    stub.SetBubbles({ b1 })
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    local mine = Bubbles.OverlayOf(b1)
    T.eq(select(2, mine:GetPoint(1)), art, "follows the balloon while it talks")
    b1:Hide()
    for i = 1, mine:GetNumPoints() do
        local _, rel = mine:GetPoint(i)
        T.truthy(rel ~= art and rel ~= b1, "fading out, no longer hung on the game's world frame")
    end
    stub.Advance(1)
    stub.RunTimers()
    T.falsy(mine:IsShown())
    T.eq(mine:GetNumPoints(), 0, "hidden with no anchor left on the game's frame")
end)

T.test("chat: speech bubbles are left to the game inside an instance, and handed back on the way in", function()
    login()
    local Bubbles = stub.chatModule.Bubbles
    local b1, art = makeBubble("Outside")
    stub.SetBubbles({ b1 })
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    T.truthy(Bubbles.OverlayOf(b1):IsShown())
    stub.SetInstance("party")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    T.eq(art:GetAlpha(), 1, "the game's own bubble back")
    T.falsy(Bubbles.OverlayOf(b1):IsShown())
    local b2, art2 = makeBubble("Inside")
    stub.SetBubbles({ b2 })
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    b1:Hide(); b1:Show()
    stub.RunTimers()
    T.isnil(Bubbles.OverlayOf(b2), "not drawn inside")
    T.eq(art2:GetAlpha(), 1)
    T.eq(art:GetAlpha(), 1, "a hooked one showing again inside is left alone too")
    stub.SetInstance("none")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.Advance(1)
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    T.truthy(Bubbles.OverlayOf(b2) and Bubbles.OverlayOf(b2):IsShown(), "drawn again outside")
end)

-- The client can lock a pooled bubble on a zone change before the loading screen's
-- event reaches Daylight UI. Its balloon can't be given its alpha back then, so it
-- stays owed and is given back once the bubble can be touched again.
T.test("chat: a bubble locked while handed back gets its balloon back once it can", function()
    login()
    local b1, art = makeBubble("Mind the gap")
    stub.SetBubbles({ b1 })
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    T.eq(art:GetAlpha(), 0, "faded while Daylight UI's frame stands in")
    art.__forbidden = true
    stub.FireEvent("LOADING_SCREEN_ENABLED")
    stub.RunTimers()
    art.__forbidden = nil
    T.eq(art:GetAlpha(), 0, "locked: the hand-back couldn't reach it")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.eq(art:GetAlpha(), 1, "given back on arriving")
    -- Owed again, then paid on the next chat line's pass instead.
    local b2, art2 = makeBubble("Again")
    stub.SetBubbles({ b2 })
    stub.Advance(1)
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    T.eq(art2:GetAlpha(), 0, "the second one drawn by Daylight UI")
    art2.__forbidden = true
    b2:Hide()
    art2.__forbidden = nil
    T.eq(art2:GetAlpha(), 0, "locked as it went: still owed")
    stub.SetBubbles({})
    stub.Advance(1)
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    T.eq(art2:GetAlpha(), 1, "given back on the next pass")
    -- A balloon Daylight UI stands in for again is no longer owed: it stays faded.
    stub.SetBubbles({ b2 })
    b2:Show()
    stub.RunTimers()
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.eq(art2:GetAlpha(), 0, "standing in again: stays faded under Daylight UI's frame")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: logging out hands every bubble back", function()
    login()
    local Bubbles = stub.chatModule.Bubbles
    local b1, art = makeBubble("Bye")
    stub.SetBubbles({ b1 })
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    T.eq(art:GetAlpha(), 0)
    stub.FireEvent("PLAYER_LOGOUT")
    T.eq(art:GetAlpha(), 1, "the game's balloon back before the reload")
end)

-- The game's bubbles sit in the world layer, which ignores the UI scale: a small
-- UI scale must not shrink the stand-in below the game's own bubble.
T.test("chat: a bubble's stand-in keeps the game bubble's size whatever the UI scale", function()
    login()
    local Bubbles = stub.chatModule.Bubbles
    local world = CreateFrame("Frame")
    local outer = CreateFrame("Frame", nil, world)
    local art = CreateFrame("Frame", nil, outer)
    local fs = art:CreateFontString()
    fs:SetFont("GameFont", 12, "")
    fs:SetText("Tiny?")
    art.String = fs
    local was = UIParent:GetScale()
    UIParent:SetScale(0.64)
    stub.SetBubbles({ outer })
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    local mine = Bubbles.OverlayOf(outer)
    T.truthy(mine and mine:IsShown(), "drawn")
    T.near(mine:GetEffectiveScale(), art:GetEffectiveScale(), 0.001, "as big as the game's bubble")
    UIParent:SetScale(1)
    DaylightUI.Fire("STYLE_CHANGED")
    stub.Advance(1)
    stub.RunTimers()
    Bubbles.Refresh()
    T.near(mine:GetEffectiveScale(), art:GetEffectiveScale(), 0.001, "and still after the UI scale changes")
    UIParent:SetScale(was)
end)

T.test("chat: a bubble with secret words is left to the game", function()
    login()
    local Bubbles = stub.chatModule.Bubbles
    local b1, art, _, fs = makeBubble("x")
    fs:SetText(stub.Secret("hidden"))
    stub.SetBubbles({ b1 })
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    local mine = Bubbles.OverlayOf(b1)
    T.truthy(not mine or not mine:IsShown(), "not drawn")
    T.eq(art:GetAlpha(), 1, "the game's own bubble shows")
end)

T.test("chat: speech bubbles can be turned off, and turning them off hands shown ones back", function()
    local DUI = login()
    local Bubbles = stub.chatModule.Bubbles
    local b1, art = makeBubble("Hi")
    stub.SetBubbles({ b1 })
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    T.eq(art:GetAlpha(), 0)
    DUI:Set("Chat", "bubbles", false)
    stub.Advance(1)
    stub.RunTimers()
    T.eq(art:GetAlpha(), 1, "handed back at once")
    T.falsy(Bubbles.OverlayOf(b1):IsShown())
    local b2, art2 = makeBubble("Hi again")
    stub.SetBubbles({ b2 })
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    T.isnil(Bubbles.OverlayOf(b2), "off: not drawn")
    T.eq(art2:GetAlpha(), 1)
end)

T.test("chat: the bubble size slider resizes bubbles without re-fonting the chat", function()
    local DUI = login()
    local Bubbles = stub.chatModule.Bubbles
    local b1 = makeBubble("Hi")
    stub.SetBubbles({ b1 })
    stub.FireEvent("CHAT_MSG_SAY")
    stub.RunTimers()
    -- Re-fonting a chat window reflows its whole history: a hitch on every slider step.
    local refreshed = 0
    local Chat = stub.chatModule.Chat
    local real = Chat.Refresh
    Chat.Refresh = function(...) refreshed = refreshed + 1; return real(...) end
    DUI:Set("Chat", "bubbleSize", 18)
    stub.Advance(1)
    stub.RunTimers()
    Chat.Refresh = real
    T.eq(refreshed, 0, "the chat left alone")
    T.eq(select(2, Bubbles.OverlayOf(b1).text:GetFont()), 18, "the shown bubble takes the new size")
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

T.test("chat: the copy window is wide, and fits a small screen", function()
    login()
    local Copy = stub.chatModule.Copy
    local w, h = Copy.Size()
    T.truthy(w >= 700 and h >= 440 or (UIParent:GetWidth() * 0.9 < 700), "wide enough, unless the screen is small")
    T.truthy(w <= UIParent:GetWidth() and h <= UIParent:GetHeight(), "never bigger than the screen")
    local was = Copy.SIZE
    Copy.SIZE = { 2000, 2000 }
    w, h = Copy.Size()
    Copy.SIZE = was
    T.truthy(w <= math.floor(UIParent:GetWidth() * 0.9) and h <= math.floor(UIParent:GetHeight() * 0.9), "cut to 90% of the screen")
end)

T.test("chat: a line the edit box won't take doesn't blank the copy window", function()
    login()
    local Copy = stub.chatModule.Copy
    ChatFrame1.lines = {}
    ChatFrame1:AddMessage("one", 1, 1, 1)
    ChatFrame1:AddMessage("bad|xline", 1, 1, 1)
    ChatFrame1:AddMessage("two", 1, 1, 1)
    stub.EditRefuses = function(t) return string.find((string.gsub(t, "||", "")), "|x", 1, true) ~= nil end
    local ok, err = pcall(Copy.Show, ChatFrame1)
    stub.EditRefuses = nil
    T.truthy(ok, err)
    local edit = _G.DaylightUIChatCopy.edit
    T.truthy(edit:GetNumLetters() > 0, "the box holds text")
    T.eq(edit.__text, "|cffffffffone|r\n||cffffffffbad||xline||r\n|cfffffffftwo|r",
        "good lines keep their colors, the refused one shows its codes")
    -- Typing restores what the box shows, not the refused text.
    edit:GetScript("OnTextChanged")(edit, true)
    T.eq(edit.__text, "|cffffffffone|r\n||cffffffffbad||xline||r\n|cfffffffftwo|r")
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
    T.eq(suppressed, tip, "off by default: only Shift compares")
    callbacks["ChatFrame.OnHyperlinkLeave"](ChatFrame1)
    suppressed = nil
    DaylightUI:Set("Chat", "linkTooltipCompare", true)
    stub.RunTimers()
    callbacks["ChatFrame.OnHyperlinkEnter"](ChatFrame1, "item:1")
    T.isnil(suppressed, "on: as the game's setting says")
    callbacks["ChatFrame.OnHyperlinkLeave"](ChatFrame1)
    DaylightUI:Set("Chat", "linkTooltipCompare", false)
    stub.RunTimers()
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

T.test("chat: the guild chat sound plays for others' guild lines, not yours, not on None, with a cooldown", function()
    local played
    login(function() played = soundFakes() end)
    local W = stub.chatModule.Whisper
    for k in pairs(played) do played[k] = nil end      -- the setup guide's open sound at login (Sound.lua)
    local function guild(event, guid)
        stub.FireEvent(event, "hi", "Someone", "", "", "", "", 0, 0, "", 0, 1, guid)
    end
    guild("CHAT_MSG_GUILD", "Player-1-OTHER")
    T.eq(#played, 0, "None by default: silent")
    DaylightUI:Set("Chat", "guildSound", "bell")
    stub.RunTimers()
    T.eq(#played, 1, "picked in the options: heard once")
    T.eq(played[1][1], W.SOUNDS.bell)
    stub.Advance(W.COOLDOWN + 1)
    guild("CHAT_MSG_GUILD", UnitGUID("player"))
    T.eq(#played, 1, "not for your own line")
    guild("CHAT_MSG_GUILD", "Player-1-OTHER")
    T.eq(#played, 2, "someone else's guild line")
    T.eq(played[2][1], W.SOUNDS.bell); T.eq(played[2][2], "SFX")
    guild("CHAT_MSG_OFFICER", "Player-1-OTHER")
    T.eq(#played, 2, "not twice inside the cooldown")
    stub.Advance(W.COOLDOWN + 1)
    guild("CHAT_MSG_OFFICER", stub.Secret("Player-1-OTHER"))
    T.eq(#played, 3, "officer chat too, and a secret GUID just plays")
    stub.Advance(W.COOLDOWN + 1)
    stub.FireEvent("CHAT_MSG_WHISPER", "hi", "Someone")
    T.eq(played[#played][1], W.SOUNDS.soft, "the whisper sound keeps its own pick")
    local play = chatItem("Play guild chat sound")
    local get = function(k) return DaylightUI:Get("Chat", k) end
    local n = #played
    play.func()
    T.eq(#played, n + 1, "Play plays it"); T.eq(played[#played][1], W.SOUNDS.bell)
    DaylightUI:Set("Chat", "guildSound", "none")
    stub.RunTimers()
    T.truthy(play.disabled(get), "None: nothing to play")
    stub.Advance(W.COOLDOWN + 1)
    n = #played
    guild("CHAT_MSG_GUILD", "Player-1-OTHER")
    T.eq(#played, n, "None: silent again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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
    -- LuaJIT's compiler allocates too, at moments that vary run to run, and code
    -- it compiled in earlier tests still runs after jit.off() unless flushed.
    -- With both done, only the addon's own garbage counts.
    if jit then jit.off(); jit.flush() end
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

T.test("chat: a whisper tab's name starts after the game's conversation icon", function()
    login()
    local Chat = stub.chatModule.Chat
    ChatFrame1Tab:Show(); ChatFrame2Tab:Show()
    -- The game adds the icon to a whisper tab, just left of its words (FCF_OpenTemporaryWindow).
    local icon = ChatFrame2Tab:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    ChatFrame2Tab.conversationIcon = icon
    ChatFrame2Tab.Left = ChatFrame2Tab:CreateTexture(nil, "BACKGROUND")
    ChatFrame2Tab.Left:SetWidth(16)
    Chat.Pass()
    local _, _, _, plain = Chat.Label(ChatFrame1Tab).text:GetPoint(1)
    local _, _, _, x = Chat.Label(ChatFrame2Tab).text:GetPoint(1)
    T.eq(plain, Chat.TAB_PAD, "a plain tab's name keeps its padding")
    T.truthy(x >= 16 + Chat.ICON_GAP, "the whisper tab's name clears the icon: " .. tostring(x))
    icon:Hide()
    Chat.Pass()
    _, _, _, x = Chat.Label(ChatFrame2Tab).text:GetPoint(1)
    T.eq(x, Chat.TAB_PAD, "with no icon it goes back")
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

-- Prat (and chat addons built like it) draws the channel as "[G] " with the space
-- inside the link and puts the name's brackets outside its link, so no "]|h" closes
-- the channel's words. The tag's pattern then ran on to the next "]|h" in the line,
-- the end of an item link, and the whole line up to it became "[G]": players saw
-- "[G]" alone (link at the end) or "[G]?" (a word after it), and two links kept the
-- second one. Seen with Russian words and English ones alike.
local PRAT_GUILD = "|Hchannel:GUILD|h[G] |h[|Hplayer:Arrling Wildheart:4612:GUILD|h29:Arrling Wildheart|h]: "
local PRAT_TRADE = "|Hchannel:channel:2|h[2. Trade] |h[|Hplayer:Kaylly Abaddon:284:CHANNEL:2|h19:Kaylly Abaddon|h]: "
local BLUNDERBUSS = "|cnIQ3:|Hitem:2099::::::::29:1485:::::::::|h[Deadly Blunderbuss]|h|r"
local SCORPID = "|cnIQ2:|Hitem:8399::::::::46:1485:::::::::|h[Pattern: Tough Scorpid Boots]|h|r"
local PRAT_LINES = {
    PRAT_GUILD .. "Всім привіт, хтось може зробити рушницю? " .. BLUNDERBUSS,
    PRAT_GUILD .. SCORPID .. "?",
    PRAT_GUILD .. SCORPID .. " and " .. BLUNDERBUSS,
    PRAT_TRADE .. "WTB " .. BLUNDERBUSS .. " 7g",
}

T.test("chat: a channel tag never runs into the item link of a line another chat addon drew", function()
    login()
    local Tags = stub.chatModule.Tags
    for _, line in ipairs(PRAT_LINES) do
        local event = line:find("channel:2", 1, true) and "CHAT_MSG_CHANNEL" or "CHAT_MSG_GUILD"
        local out = Tags.Shape(line, event) or line
        T.eq(out, line, "the line keeps every word and link")
    end
    -- The game's own lines are still shortened, link and all.
    local game = "|Hchannel:GUILD|h[Guild]|h |Hplayer:Bob:1:GUILD|h[Bob]|h: " .. BLUNDERBUSS
    T.eq(Tags.Shape(game, "CHAT_MSG_GUILD"), "|Hchannel:GUILD|h[G]|h |Hplayer:Bob:1:GUILD|h[Bob]|h: " .. BLUNDERBUSS)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: those lines keep their words and links in the Classic window", function()
    login()
    stub.chatModule.Chat.Pass()
    local cf = ChatFrame1
    for _, line in ipairs(PRAT_LINES) do cf:AddMessage(line, 0.25, 1, 0.25, 3) end
    cf:FakeRefresh()
    for i, line in ipairs(PRAT_LINES) do
        T.eq(cf.visibleLines[#PRAT_LINES + 1 - i]:GetText(), line, "drawn whole")
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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

-- The game announces a typing box's focus change through EventRegistry
-- (ChatFrameEditBox.lua, from the box's own focus scripts).
local function announce(event, eb)
    local cb = callbacks["ChatFrame.OnEditBox" .. event]
    if cb then cb(eb) end
end

T.test("chat: the typing box eases in out of a fight and snaps in one", function()
    login()
    local Chat = stub.chatModule.Chat
    local eb = ChatFrame1EditBox
    local focused = false
    function eb:HasFocus() return focused end
    Chat.Step(1)
    focused = true
    announce("FocusGained", eb)
    Chat.Step(DaylightUI.Motion.FAST / 2)
    T.truthy(eb:GetAlpha() > 0 and eb:GetAlpha() < 1, "on its way in: " .. eb:GetAlpha())
    T.truthy(eb:IsMouseEnabled(), "typing at once")
    focused = false
    Chat.Step(1)
    Chat.fight = true
    focused = true
    announce("FocusGained", eb)
    Chat.Step(0.01)
    T.eq(eb:GetAlpha(), 1, "in a fight: at once")
    Chat.fight = nil
end)

-- Idle chat used to look at every typing box every frame (HasFocus, alpha, outline
-- color), about 14 boxes, 60+ times a second. The game says when a box's focus
-- changes, so the boxes are only looked at around those changes and while typing.
T.test("chat: idle typing boxes aren't looked at every frame, a focus change shows the box at once", function()
    login()
    local Chat = stub.chatModule.Chat
    local eb = ChatFrame1EditBox
    local focused, looks = false, 0
    function eb:HasFocus() looks = looks + 1; return focused end
    for _ = 1, 30 do Chat.Step(1 / 60) end   -- settle whatever login left
    looks = 0
    for _ = 1, 60 do Chat.Step(1 / 60) end   -- one idle second
    T.truthy(looks <= 1 / Chat.WATCH + 1, "an idle second: a few looks, not one a frame (" .. looks .. ")")
    -- Enter: the game focuses the box and says so; the very next frame shows it.
    focused = true
    announce("FocusGained", eb)
    Chat.Step(1 / 60)
    T.truthy(eb:GetAlpha() > 0, "typing: on its way in the next frame")
    T.truthy(eb:IsMouseEnabled(), "and takes clicks at once")
    looks = 0
    for _ = 1, 10 do Chat.Step(1 / 60) end
    T.truthy(looks >= 10, "while typing it's followed every frame (a channel switch recolors it)")
    T.eq(eb:GetAlpha(), 1)
    -- Sent: focus lost is announced first, then the game sets the idle box to 0.35.
    focused = false
    announce("FocusLost", eb)
    eb:SetAlpha(0.35)
    for _ = 1, 30 do Chat.Step(1 / 60) end
    T.eq(eb:GetAlpha(), 0, "the game's 0.35 is taken back down")
    T.falsy(eb:IsMouseEnabled(), "clicks go through to the tabs again")
    -- A box whose focus reads secret and no announcement: caught by the slow look.
    focused = true
    for _ = 1, math.ceil(Chat.WATCH * 60) + 2 do Chat.Step(1 / 60) end
    T.truthy(eb:GetAlpha() > 0, "missed edge: seen within one watch")
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

-- The same lines (Prat's shape, test above) in the box: the words and every link stay.
T.test("chat daylight: a line another chat addon drew keeps its words and links in the box", function()
    local _, box = daylight()
    for _, line in ipairs(PRAT_LINES) do ChatFrame1:AddMessage(line, 0.25, 1, 0.25, 3) end
    local texts = boxTexts(box)
    for i, line in ipairs(PRAT_LINES) do
        local got = texts[#texts - #PRAT_LINES + i] or ""
        T.truthy(got:find(line:match("|h%]: (.*)$"), 1, true), "the words and links: " .. got)
        T.truthy(got:find("[G] |h", 1, true) or got:find("[2. Trade] |h", 1, true), "and the addon's own tag")
    end
    -- A name whose "]" isn't right before its link's end keeps its brackets.
    local odd = "|Hchannel:GUILD|h[Guild]|h |Hplayer:Bob:1:GUILD|h[Bob] |h: hi " .. SCORPID
    ChatFrame1:AddMessage(odd, 0.25, 1, 0.25, 3, nil, nil, "CHAT_MSG_GUILD", { "hi", "Bob", n = 14 })
    texts = boxTexts(box)
    T.truthy(texts[#texts]:find("[Bob] |h: hi " .. SCORPID, 1, true), texts[#texts])
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- An NPC's emote is its text with the name apart (arg 2). A line the game made without
-- the name gets it in the box, after the timestamp.
-- Turning Experience off left "Experience gained: 975." from a quest in the tab:
-- the game sends quest rewards as system messages.
T.test("chat daylight: a quest's experience, money and item lines go by their own switches", function()
    local _, box = daylight()
    local Kinds = stub.chatModule.Kinds
    _G.ERR_QUEST_REWARD_EXP_I = "Experience gained: %d."    -- the game's GlobalStrings
    _G.ERR_QUEST_REWARD_MONEY_S = "Received %s."
    _G.ERR_QUEST_REWARD_ITEM_S = "Received item: %s."
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_SYSTEM", {}, "Experience gained: 975.")), "progress")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_SYSTEM", {}, "19:31:43 Experience gained: 975.")), "progress", "after a time stamp")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_SYSTEM", {}, "Received 4 Silver.")), "money")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_SYSTEM", {}, "Received item: |cff1eff00|Hitem:1|h[Shovel]|h|r.")), "loot",
        "an item, not money")
    T.eq(select(2, Kinds.Of(nil, "CHAT_MSG_SYSTEM", {}, "Quest accepted: Scramble")), "system")
    -- A tab with System on and Experience off no longer shows it.
    local tab = { name = "T", kinds = { system = true }, v = Kinds.VERSION }
    T.falsy(Kinds.Shows(tab, select(2, Kinds.Of(nil, "CHAT_MSG_SYSTEM", {}, "Experience gained: 975."))))
    T.truthy(Kinds.Shows(tab, select(2, Kinds.Of(nil, "CHAT_MSG_SYSTEM", {}, "Quest accepted: Scramble"))))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: an NPC emote the game made without its name gets the name", function()
    local Box, box = daylight()
    local function emote(text, name, id)
        ChatFrame1:AddMessage(text, 1, 0.5, 0.25, id, nil, nil, "CHAT_MSG_MONSTER_EMOTE", { "intenta huir.", name, n = 14, [11] = id })
    end
    emote("intenta huir.", "Guerrero", 41)
    emote("11:50 intenta huir.", "Guerrero", 42)
    emote("Guerrero intenta huir.", "Guerrero", 43)
    emote("intenta huir.", stub.Secret("Guerrero"), 44)
    emote("intenta huir.", "", 45)
    ChatFrame1:AddMessage("intenta huir.", 1, 0.5, 0.25, 46, nil, nil, "CHAT_MSG_MONSTER_SAY", { "intenta huir.", "Guerrero", n = 14, [11] = 46 })
    local texts = boxTexts(box)
    T.eq(texts[1], "Guerrero intenta huir.", "the name in front")
    T.truthy(string.find(texts[2], "11:50|r Guerrero intenta huir.", 1, true), "after the timestamp: " .. texts[2])
    T.eq(texts[3], "Guerrero intenta huir.", "a line that has it already stays as it was")
    T.eq(texts[4], "intenta huir.", "a secret name can't be read: left alone")
    T.eq(texts[5], "intenta huir.", "no name: left alone")
    T.eq(texts[6], "intenta huir.", "only emotes")
    T.eq(ChatFrame1.lines[1][1], "intenta huir.", "the game's own line untouched")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

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

-- The game's default chat settings send experience from kills only to the
-- combat log window, which the box never reads: the box takes those lines from
-- the event itself, once, and only while no window it reads carries them.
local function dropGroup(cf, group)
    for i, g in pairs(cf.messageTypeList) do if g == group then cf.messageTypeList[i] = nil end end
end
T.test("chat daylight: experience from kills shows though only the combat log carries it", function()
    local Box, box = daylight(function()
        _G.ChatTypeInfo.COMBAT_XP_GAIN = { id = 9, r = 0.4, g = 0.4, b = 1 }
        _G.COMBATLOG = ChatFrame2
    end)
    -- As the game's defaults: only the combat log window (ChatFrame2) has it.
    for i = 1, 10 do
        local cf = _G["ChatFrame" .. i]
        if i ~= 2 and cf and cf.messageTypeList then dropGroup(cf, "COMBAT_XP_GAIN") end
    end
    T.truthy(ChatFrame2:ContainsMessageGroup("COMBAT_XP_GAIN"))
    local text = "Young Wolf dies, you gain 45 experience."
    stub.FireEvent("CHAT_MSG_COMBAT_XP_GAIN", text, "", "", "", "", "", 0, 0, "", 0, 0)
    Box.Pick(4)
    local texts = table.concat(boxTexts(box), "|")
    T.truthy(texts:find("you gain 45 experience", 1, true), "on Loot: " .. texts)
    Box.Pick(1)
    texts = table.concat(boxTexts(box), "|")
    T.falsy(texts:find("you gain 45 experience", 1, true), "not on General: " .. texts)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: saved everything tabs leave experience out, picked tabs keep it", function()
    local Kinds = stub.chatModule.Kinds
    local all = { name = "General", all = true, kinds = { tradeskill = false }, v = 7 }
    local loot = { name = "Loot", kinds = { loot = true, progress = true }, v = 7 }
    Kinds.Upgrade(all)
    Kinds.Upgrade(loot)
    T.falsy(Kinds.Shows(all, "progress"), "no kill experience on the everything tab")
    T.truthy(Kinds.Shows(all, "loot") and all.all, "still everything else")
    T.truthy(Kinds.Shows(loot, "progress"), "a tab picked for it keeps it")
    T.eq(all.v, Kinds.VERSION)
end)

T.test("chat daylight: a line no game window has stays out of the box", function()
    local Box, box = daylight(function()
        _G.ChatTypeInfo.COMBAT_XP_GAIN = { id = 9, r = 0.4, g = 0.4, b = 1 }
    end)
    -- Switched off in every window in the game's chat settings.
    for i = 1, 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.messageTypeList then dropGroup(cf, "COMBAT_XP_GAIN") end
    end
    stub.FireEvent("CHAT_MSG_COMBAT_XP_GAIN", "Young Wolf dies, you gain 45 experience.", "", "", "", "", "", 0, 0, "", 0, 0)
    Box.Pick(1)
    local texts = table.concat(boxTexts(box), "|")
    T.falsy(texts:find("you gain 45 experience", 1, true), "switched off everywhere: " .. texts)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: saved tabs drop the crafting lines too", function()
    local Box, box = daylight(function()
        _G.ChatTypeInfo.TRADESKILLS = { id = 30, r = 1, g = 1, b = 1 }
        _G.COMBATLOG = ChatFrame2
    end)
    -- As the game's defaults: crafting goes only to the combat log window.
    for i = 1, 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.messageTypeList then
            dropGroup(cf, "TRADESKILLS")
            if i == 2 then cf.messageTypeList[#cf.messageTypeList + 1] = "TRADESKILLS" end
        end
    end
    -- Tabs a player renamed or changed: saved whole, at an older tab version.
    DaylightUI:Set("Chat", "tabs", {
        { name = "Mine", all = true, v = 6 },
        { name = "Loot", kinds = { loot = true, tradeskill = true }, v = 6 },
        { name = "Old", kinds = { loot = true }, v = 5 },
    })
    stub.RunTimers()
    local Kinds = stub.chatModule.Kinds
    local tabs = Box.Tabs()
    T.truthy(tabs[1].all, "still an everything tab")
    T.falsy(Kinds.Shows(tabs[1], "tradeskill"), "no crafting on the everything tab")
    T.truthy(Kinds.Shows(tabs[1], "say") and Kinds.Shows(tabs[1], "loot"), "the rest stays")
    T.falsy(Kinds.Shows(tabs[2], "tradeskill"), "nor on a saved loot tab")
    T.truthy(Kinds.Shows(tabs[2], "loot"), "loot stays")
    T.falsy(Kinds.Shows(tabs[3], "tradeskill"), "an older tab skips it through the split")
    T.truthy(Kinds.Shows(tabs[3], "opening"), "while the split's other kinds still come")
    stub.FireEvent("CHAT_MSG_TRADESKILLS", "Somebody creates Linen Bandage.", "", "", "", "", "", 0, 0, "", 0, 0)
    Box.Pick(1)
    local texts = table.concat(boxTexts(box), "|")
    T.falsy(texts:find("creates Linen Bandage", 1, true), "a busy city stays quiet: " .. texts)
    -- Switched back on, it shows and stays on after the next read.
    stub.chatModule.Tabs.SetKind(1, "tradeskill", true)
    stub.RunTimers()
    T.truthy(Kinds.Shows(Box.Tabs()[1], "tradeskill"), "a player can still turn it on")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's chat never fills with every nearby player's crafting, even with
-- Tradeskills on: only "You create..." comes through.
T.test("chat daylight: Tradeskills on shows your crafting, never everyone else's", function()
    local Box, box = daylight(function()
        _G.ChatTypeInfo.TRADESKILLS = { id = 30, r = 1, g = 1, b = 1 }
        _G.COMBATLOG = ChatFrame2
        _G.TRADESKILL_LOG_FIRSTPERSON = "You create %s."
        _G.TRADESKILL_LOG_THIRDPERSON = "%s creates %s."
    end)
    for i = 1, 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.messageTypeList then
            dropGroup(cf, "TRADESKILLS")
            if i == 2 then cf.messageTypeList[#cf.messageTypeList + 1] = "TRADESKILLS" end
        end
    end
    stub.chatModule.Tabs.SetKind(1, "tradeskill", true)
    stub.RunTimers()
    Box.Pick(1)
    local me = UnitGUID("player")
    local function fire(text, guid)
        stub.FireEvent("CHAT_MSG_TRADESKILLS", text, "", "", "", "", "", 0, 0, "", 0, 0, guid or "")
    end
    fire("Xara Dawnspire creates Heavy Wool Bandage.", "Player-1-00000099")
    fire("Somebody creates Linen Bandage.")
    fire("You create Silk Bandage.", me)
    -- A game window that carries the group: its lines reach the box through the hook.
    ChatFrame1.messageTypeList[#ChatFrame1.messageTypeList + 1] = "TRADESKILLS"
    local args = { "Bob Stone creates Copper Bracers.", "", n = 14 }
    args[12] = "Player-1-00000098"
    ChatFrame1:AddMessage(args[1], 1, 1, 1, 30, nil, nil, "CHAT_MSG_TRADESKILLS", args)
    local texts = table.concat(boxTexts(box), "|")
    T.falsy(texts:find("Heavy Wool Bandage", 1, true), "another player's, by GUID: " .. texts)
    T.falsy(texts:find("Linen Bandage", 1, true), "another player's, by the game's words: " .. texts)
    T.falsy(texts:find("Copper Bracers", 1, true), "nor through a game window: " .. texts)
    T.truthy(texts:find("You create Silk Bandage.", 1, true), "your own still shows: " .. texts)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Only the gains the game's defaults leave in the combat log come over. The
-- log's own stream (pets eating, misc combat lines) stays there.
T.test("chat daylight: combat log lines never come over into the box", function()
    local Box, box = daylight(function()
        _G.ChatTypeInfo.COMBAT_MISC_INFO = { id = 10, r = 1, g = 1, b = 1 }
        _G.ChatTypeInfo.PET_INFO = { id = 11, r = 1, g = 1, b = 1 }
        _G.COMBATLOG = ChatFrame2
    end)
    for i = 1, 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.messageTypeList then
            dropGroup(cf, "COMBAT_MISC_INFO"); dropGroup(cf, "PET_INFO")
        end
    end
    local log = ChatFrame2
    log.messageTypeList[#log.messageTypeList + 1] = "COMBAT_MISC_INFO"
    log.messageTypeList[#log.messageTypeList + 1] = "PET_INFO"
    stub.FireEvent("CHAT_MSG_COMBAT_MISC_INFO", "Spoof's pet begins eating a Roasted Quail.", "", "", "", "", "", 0, 0, "", 0, 0)
    stub.FireEvent("CHAT_MSG_PET_INFO", "Your pet is happy.", "", "", "", "", "", 0, 0, "", 0, 0)
    Box.Pick(1)
    local texts = table.concat(boxTexts(box), "|")
    T.falsy(texts:find("begins eating", 1, true), "misc line stayed out: " .. texts)
    T.falsy(texts:find("pet is happy", 1, true), "pet line stayed out: " .. texts)
end)

T.test("chat daylight: a window that carries experience lines keeps them single", function()
    local Box, box = daylight(function()
        _G.ChatTypeInfo.COMBAT_XP_GAIN = { id = 9, r = 0.4, g = 0.4, b = 1 }
    end)
    local Kinds = stub.chatModule.Kinds
    local text = "Young Wolf dies, you gain 45 experience."
    stub.FireEvent("CHAT_MSG_COMBAT_XP_GAIN", text, "", "", "", "", "", 0, 0, "", 0, 0)
    Kinds.Filter(ChatFrame1, "CHAT_MSG_COMBAT_XP_GAIN", text)
    ChatFrame1:AddMessage(text, 0.4, 0.4, 1, 9)
    Box.Pick(4)   -- Loot: General leaves experience out
    local n = 0
    for _, t in ipairs(boxTexts(box)) do if t:find("you gain 45 experience", 1, true) then n = n + 1 end end
    T.eq(n, 1, "once")
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
    box:GetScript("OnHyperlinkClick")(box, "item:2589", "[Linen Cloth]", "LeftButton")
    T.eq(got and got[1], "item:2589")
    T.eq(got[4], DEFAULT_CHAT_FRAME, "as if clicked in the main window")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A click that misses the twins lands on the box itself (a line the twins skip,
-- such as one whose text read secret). Run from there, the game's name menu
-- carries Daylight UI's taint and its Guild Invite is blocked ("the game
-- blocked Invite()", a player's report), as Copy Character Name was. So a name
-- or channel clicked on the box itself never reaches the game's click: the
-- twins are laid again, and the next click is the game's own.
T.test("chat daylight: a name or channel clicked on the box itself never runs the game's click from Daylight UI", function()
    local _, box = daylight()
    local CH = stub.chatModule
    local calls, synced = 0, 0
    _G.SetItemRef = function() calls = calls + 1 end
    local sync = CH.Links.Sync
    CH.Links.Sync = function(...) synced = synced + 1; return sync(...) end
    for _, link in ipairs({ "player:Robb-Realm:77:GUILD", "BNplayer:Kira:3:78:BN_WHISPER",
                            "playerCommunity:Robb:1", "channel:CHANNEL:2" }) do
        for _, button in ipairs({ "LeftButton", "RightButton" }) do
            box:GetScript("OnHyperlinkClick")(box, link, "[x]", button)
        end
    end
    CH.Links.Sync = sync
    T.eq(calls, 0, "the game's click never ran from the box's own script")
    T.truthy(synced >= 1, "the twins were laid again for the next click")
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

-- A profession link (and a recipe's) opens only from the game's own click: one
-- passed on from the box's script reached SetItemRef and the game opened nothing
-- (seen in game). Each shown line has an invisible twin over it on a frame made
-- from the game's InlineHyperlinkFrameTemplate, whose click is the game's.
local function twinOf(CH, box, i)
    local m = CH.Links.Mirror(box)
    local t = m and m.lines[i]
    if t and t:IsShown() then return t end
end

T.test("chat daylight: a profession link is clicked through the game's own link frame", function()
    local _, box = daylight()
    local CH = stub.chatModule
    local got = {}
    _G.SetItemRef = function(link, text, button, frame)
        got[#got + 1] = { link = link, game = (stub.gameClick or 0) > 0, frame = frame }
    end
    local link = "trade:Player-6928-01B3BE12:3100:164"
    local text = "|cffffd000|H" .. link .. "|h[Tailoring]|h|r"
    local channel = "|Hchannel:channel:2|h[2. Trade]|h"
    box:AddMessage(channel .. " Robb: " .. text)
    box:FakeRefresh()
    local m = CH.Links.Mirror(box)
    T.truthy(m and m:IsShown(), "the lines' twins are up")
    T.eq(m:GetParent(), box)
    T.eq(m:GetAlpha(), 0, "never seen: the box's own lines show")
    T.eq(m:IsMouseEnabled(), false, "the wheel and drags still reach the box")
    T.eq(m:GetHyperlinksEnabled(), true)
    local t = twinOf(CH, box, 1)
    T.truthy(t, "the line with the link has its twin")
    T.eq(select(2, t:GetPoint(1)), box.visibleLines[1], "laid exactly over its line")
    T.eq(t:GetText(), channel .. " Robb: " .. text, "the channel and the profession both links")

    -- Hovering the twin's link shows the box's tooltip.
    local entered, left = {}, 0
    local enter, leave = CH.LinkTips.OnEnter, CH.LinkTips.OnLeave
    CH.LinkTips.OnEnter = function(f, l) entered[#entered + 1] = { f, l } end
    CH.LinkTips.OnLeave = function() left = left + 1 end
    m:GetScript("OnHyperlinkEnter")(m, link, text)
    T.eq(entered[1] and entered[1][1], box)
    T.eq(entered[1] and entered[1][2], link)

    m:GetScript("OnHyperlinkClick")(m, link, text, "LeftButton")
    T.eq(#got, 1)
    T.eq(got[1].link, link)
    T.truthy(got[1].game, "SetItemRef ran as the game's code")
    T.truthy(m:IsShown(), "still there for the next click")
    m:GetScript("OnHyperlinkLeave")(m)
    T.eq(left, 1)
    CH.LinkTips.OnEnter, CH.LinkTips.OnLeave = enter, leave
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A name's right-click menu built from an addon's click carries the addon's
-- taint, and its Copy Character Name was blocked (ADDON_ACTION_FORBIDDEN on
-- CopyToClipboard, seen in game). So names are clicked through the twin too.
T.test("chat daylight: a name is clicked through the game's own link frame, so its menu is the game's", function()
    local Box, box = daylight()
    local CH = stub.chatModule
    local got = {}
    _G.SetItemRef = function(link, text, button)
        got[#got + 1] = { link = link, button = button, game = (stub.gameClick or 0) > 0 }
    end
    local name = "|Hplayer:Robb-Realm:77:GUILD|h[Robb]|h"
    local bn = "|HBNplayer:Kira:3:78:BN_WHISPER|h[Kira]|h"
    box:AddMessage(name .. ": hi")
    box:AddMessage(bn .. ": yo")
    box:FakeRefresh()
    local t1, t2 = twinOf(CH, box, 1), twinOf(CH, box, 2)
    T.truthy(t1 and t2, "a line with only a name gets its twin")
    T.truthy(string.find(t1:GetText(), "|Hplayer:", 1, true) or string.find(t2:GetText(), "|Hplayer:", 1, true),
        "the name stays a link in the twin")
    local m = CH.Links.Mirror(box)
    local link = "player:Robb-Realm:77:GUILD"
    m:GetScript("OnHyperlinkClick")(m, link, "[Robb]", "RightButton")
    T.eq(#got, 1)
    T.eq(got[1].button, "RightButton")
    T.truthy(got[1].game, "the menu opens from the game's own click")
    -- Shift-click still sends a /who, and its answer still shows on the tab you asked from.
    local asked = 0
    local was = Box.Asked
    Box.Asked = function() asked = asked + 1 end
    local mod = _G.IsModifiedClick
    _G.IsModifiedClick = function(k) return k == "CHATLINK" end
    m:GetScript("OnHyperlinkClick")(m, link, "[Robb]", "LeftButton")
    _G.IsModifiedClick = mod
    Box.Asked = was
    T.eq(asked, 1, "the box knows a /who was asked")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game hides a message it thinks is inappropriate behind a "Show Message"
-- link. Its click rewrites that line in the game's own windows only
-- (ItemRefHandlersShared.lua: TransformMessages, no AddMessage), so the box has
-- to take the shown message from there.
T.test("chat daylight: Show Message on a hidden message shows it in the box", function()
    local _, box = daylight()
    local CH = stub.chatModule
    local hidden = "Message from Robb is potentially inappropriate. |Hcensoredmessage:77|h[Show Message]|h"
    said(ChatFrame1, "before", "CHAT_MSG_SAY", 76)
    said(ChatFrame1, hidden, "CHAT_MSG_WHISPER", 77)
    said(ChatFrame1, "after", "CHAT_MSG_SAY", 78)
    -- The game's handler, as in its source: every window's line with this id rewritten.
    _G.SetItemRef = function(link)
        local id = tonumber(string.match(link, "^censoredmessage:(%d+)"))
        if not id then return end
        ChatFrame1:TransformMessages(function(_, _, _, _, _, _, _, _, args) return args[11] == id end,
            function(_, r, g, b, infoID, accessID, typeID, event, args, ...)
                return "[Robb] whispers: hello there |Hreportcensoredmessage:77|h[Report]|h", r, g, b,
                    infoID, accessID, typeID, event, args, ...
            end)
    end
    box:FakeRefresh()
    local m = CH.Links.Mirror(box)
    T.truthy(m and m:IsShown(), "clicked through the game's own link frame")
    m:GetScript("OnHyperlinkClick")(m, "censoredmessage:77", "[Show Message]", "LeftButton")
    local texts = boxTexts(box)
    T.eq(#texts, 3, "still three lines")
    T.eq(texts[1], "before")
    T.truthy(string.find(texts[2], "hello there", 1, true), "the message shows in its place: " .. tostring(texts[2]))
    T.eq(texts[3], "after", "in the same order")
    -- Switching tabs fills the box from its kept lines: the message stays shown.
    CH.Box.Pick(CH.Box.Picked())
    T.truthy(string.find(boxTexts(box)[2], "hello there", 1, true), "kept")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- In a whisper conversation an item link and the game's Show Message did nothing:
-- its lines were plain text with no link frame under them.
T.test("chat daylight: a whisper conversation's links are the game's click, and Show Message shows it there", function()
    local _, box = daylight()
    local CH = stub.chatModule
    local hidden = "Message from Robb is potentially inappropriate. |Hcensoredmessage:77|h[Show Message]|h"
    _G.CHAT_WHISPER_GET = "%s whispers: "   -- the game's GlobalStrings
    stub.FireEvent("CHAT_MSG_WHISPER", hidden, "Robb", "", "", "", "", 0, 0, "", 0, 77, "Player-1-0002")
    local args = { hidden, "Robb", n = 14 }
    args[11] = 77
    ChatFrame1:AddMessage(hidden, 1, 1, 1, 3, nil, nil, "CHAT_MSG_WHISPER", args)
    _G.SetItemRef = function(link)
        local id = tonumber(string.match(link, "^censoredmessage:(%d+)"))
        if not id then return end
        ChatFrame1:TransformMessages(function(_, _, _, _, _, _, _, _, a) return a[11] == id end,
            function(_, r, g, b, infoID, accessID, typeID, event, a, ...)
                return "|Hplayer:Robb|h[Robb]|h whispers: hello there |Hreportcensoredmessage:77|h[Report]|h", r, g, b,
                    infoID, accessID, typeID, event, a, ...
            end)
    end
    CH.Convo.Open("w:Robb")
    local t = CH.Convo.Thread()
    local row = t.rows[1]
    T.truthy(row and row.__links, "the line sits on the game's own link frame")
    T.falsy(row:IsMouseEnabled(), "the wheel still reaches the list")
    row:GetScript("OnHyperlinkClick")(row, "censoredmessage:77", "[Show Message]", "LeftButton")
    T.eq(CH.Talk.Get("w:Robb").msgs[1].text, "hello there", "the conversation shows the message")
    T.eq(t.rows[1].text:GetText(), "hello there", "redrawn")
    CH.Convo.Close()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: Daylight UI's own links stay the box's click", function()
    local _, box = daylight()
    local CH = stub.chatModule
    for _, link in ipairs({ "clubTicket:ABC",
                            "questie:12:Bob", "addon:DaylightUI:url:x", "daylightchat:spam:all" }) do
        box:AddMessage("|H" .. link .. "|h[x]|h")
    end
    -- A secret line (chat lockdown) is left alone too.
    box:AddMessage(stub.Secret("|Hitem:19019|h[Thunderfury]|h"))
    box:FakeRefresh()
    for i = 1, 5 do T.falsy(twinOf(CH, box, i), "line " .. i .. " has no twin") end
    local m = CH.Links.Mirror(box)
    T.falsy(m and m:IsShown(), "nothing for the game to click")
    T.eq(CH.Links.Twin("|Hquestie:12:Bob|h[Q]|h |Hplayer:Bob|h[Bob]|h: |Hitem:1|h[A]|h"),
        "[Q] |Hplayer:Bob|h[Bob]|h: |Hitem:1|h[A]|h")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The REPLY key in a battleground errored "attempt to compare local 'value' (a
-- secret string value, while execution tainted by 'DaylightUI_Chat')": a channel
-- tag clicked in the box ran the game's OpenChat from Daylight UI's code, which
-- left the game's LAST_ACTIVE_CHAT_EDIT_BOX tainted for the reply to read.
T.test("chat daylight: a channel tag's click is the game's, so a whisper reply stays clean", function()
    local _, box = daylight()
    local CH = stub.chatModule
    stub.Mark(nil, "LAST_ACTIVE_CHAT_EDIT_BOX", nil)
    local opened = {}
    -- ActivateChat inside the game's OpenChat writes the global.
    _G.ChatFrameUtil.OpenChat = function(text)
        opened[#opened + 1] = text
        stub.SetLastActiveWindow(ChatFrame1EditBox)
    end
    -- The game's channel handler (ItemRefHandlersShared.lua), its left click.
    _G.SetItemRef = function(link, _, button)
        local kind, target = string.match(link, "^channel:(%a+):?(%d*)")
        if kind and button == "LeftButton" then
            _G.ChatFrameUtil.OpenChat("/" .. (target ~= "" and target or kind))
        end
    end
    box:AddMessage("|Hchannel:CHANNEL:2|h[T]|h |Hplayer:Robb|h[Robb]|h: WTS")
    box:AddMessage("|Hchannel:GUILD|h[G]|h Ann: hi")
    box:FakeRefresh()
    -- A click lands on a twin that holds the link, else on the box under it.
    local function click(link, text)
        for i = 1, 2 do
            local t = twinOf(CH, box, i)
            if t and string.find(t:GetText(), "|H" .. link .. "|h", 1, true) then
                local m = CH.Links.Mirror(box)
                return m:GetScript("OnHyperlinkClick")(m, link, text, "LeftButton")
            end
        end
        box:GetScript("OnHyperlinkClick")(box, link, text, "LeftButton")
    end
    click("channel:CHANNEL:2", "[T]")
    click("channel:GUILD", "[G]")
    T.deq(opened, { "/2", "/GUILD" }, "the game opened the box for each channel")
    T.noerror(function() stub.ReplyTell(stub.Secret("Robb-Realm")) end, "reply")
    stub.Mark(nil, "LAST_ACTIVE_CHAT_EDIT_BOX", nil)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Picking the combat log tab once selected it in the dock from Daylight UI's
-- code: the dock hid ChatFrame1, and its box's OnHide handed the game's
-- LAST_ACTIVE_CHAT_EDIT_BOX to the combat log's box, tainted (the IM chat style).
T.test("chat daylight: the combat log tab leaves the box a reply opens clean", function()
    local selected
    local Box = daylight(function()
        -- The game's dock shows its selected window and hides the others (FCFDock_UpdateTabs).
        _G.FCFDock_SelectWindow = function(_, cf)
            selected = cf
            for _, w in ipairs({ ChatFrame1, ChatFrame2 }) do w:SetShown(w == cf) end
        end
        _G.FCFDock_GetSelectedWindow = function() return selected end
        selected = ChatFrame1
        for _, n in ipairs({ 1, 2 }) do
            local cf, eb = _G["ChatFrame" .. n], _G["ChatFrame" .. n .. "EditBox"]
            eb:SetParent(cf)   -- the template's box is the window's child
            cf.editBox = eb
            stub.ChatEditBoxOnHide(eb)
        end
    end)
    local CH = stub.chatModule
    stub.Mark(nil, "LAST_ACTIVE_CHAT_EDIT_BOX", nil)
    ChatFrame1EditBox:Show()
    stub.SetLastActiveWindow(ChatFrame1EditBox)   -- the game's own pick
    local i = CH.Tabs.Add(true)
    stub.RunTimers()
    Box.Pick(i)
    CH.Chat.Pass()
    T.truthy(ChatFrame2:IsVisible(), "the combat log shows")
    T.eq(ChatFrame2:GetAlpha(), 1, "and is seen")
    T.noerror(function() stub.ReplyTell(stub.Secret("Robb-Realm")) end, "reply with the combat log picked")
    Box.Pick(1)
    CH.Chat.Pass()
    T.falsy(ChatFrame2:IsShown(), "put away again")
    T.noerror(function() stub.ReplyTell(stub.Secret("Robb-Realm")) end, "reply after")
    stub.Mark(nil, "LAST_ACTIVE_CHAT_EDIT_BOX", nil)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Only rows that held a link get a twin, so the list of twins has holes. When the
-- game lays the box out again (a resize, a new font) it keeps fewer rows
-- (ScrollingMessageFrame RefreshLayout), and hiding the twins past the last row
-- by counting them hit a hole: "attempt to index field '?'" (seen 10 times).
T.test("chat daylight: twins past the last row hide even with rows that never had a link", function()
    local _, box = daylight()
    local CH = stub.chatModule
    local link = "|Henchant:3915|h[Tailoring: Bolt of Linen]|h"
    box:AddMessage("top " .. link)   -- row 4
    box:AddMessage("plain words")    -- row 3, never a twin
    box:AddMessage("two " .. link)   -- row 2
    box:AddMessage("one " .. link)   -- row 1, the newest
    box:FakeRefresh()
    T.truthy(twinOf(CH, box, 4), "the top row's link has its twin")
    T.falsy(CH.Links.Mirror(box).lines[3], "the plain row never got one")
    -- The game's new layout keeps two rows, then redraws.
    for i = #box.visibleLines, 3, -1 do
        box.visibleLines[i]:Hide()
        box.visibleLines[i] = nil
    end
    for _, fn in ipairs(box.onDisplayRefreshedCallbacks) do fn(box) end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.falsy(twinOf(CH, box, 4), "the twin of a row that's gone is hidden")
    T.truthy(twinOf(CH, box, 1) and twinOf(CH, box, 2), "the rows still shown keep theirs")
end)

-- New lines in a busy channel and scrolling move the links: the twins follow, so
-- the click always lands on the link that's shown.
T.test("chat daylight: the twins follow new lines and scrolling", function()
    local _, box = daylight()
    local CH = stub.chatModule
    local link = "|Henchant:3915|h[Tailoring: Bolt of Linen]|h"
    box:AddMessage("recipe " .. link)
    box:FakeRefresh()
    T.eq(twinOf(CH, box, 1):GetText(), "recipe " .. link)
    box:AddMessage("just talk")
    box:FakeRefresh()
    T.falsy(twinOf(CH, box, 1), "the bottom line has no link now")
    T.eq(twinOf(CH, box, 2):GetText(), "recipe " .. link, "the link's twin moved up with it")
    box:ScrollUp()
    box:FakeRefresh()
    T.eq(twinOf(CH, box, 1):GetText(), "recipe " .. link, "and back down when scrolled")
    -- The box's font follows the style: the twin wraps the same way.
    box:SetFont("Fonts/ARIALN.TTF", 18, "")
    box:FakeRefresh()
    T.eq(select(2, twinOf(CH, box, 1):GetFont()), 18)
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

-- With a class accent the mention was lit in the class gradient's middle, and a
-- warlock's name lit in chat didn't match the warlock color the game gives names.
T.test("chat daylight: with a class accent a mention is lit in the class color names have", function()
    local _, box = daylight()
    local me = UnitName("player")
    stub.units.player = stub.units.player or { name = me, isPlayer = true }
    stub.units.player.class = "MAGE"
    local c = RAID_CLASS_COLORS.MAGE
    local want = DaylightUI.Win.Parts.Hex({ c.r, c.g, c.b })
    for i, accent in ipairs({ "classGradient", "class" }) do
        DaylightUI:Set("general", "accent", accent)
        stub.RunTimers()
        said(ChatFrame1, "is " .. me .. " coming? " .. i, "CHAT_MSG_GUILD", 10 + i)
        local texts = boxTexts(box)
        local text = texts[#texts]
        T.truthy(string.find(text, " " .. i, 1, true), "the newest line")
        T.truthy(string.find(text, want .. me, 1, true), accent .. ": the name in the class color: " .. text)
    end
    DaylightUI:Set("general", "accent", "daylight")
    stub.RunTimers()
    said(ChatFrame1, "is " .. me .. " here?", "CHAT_MSG_GUILD", 20)
    local a = DaylightUI.Win.Parts.Hex({ DaylightUI.Style.Accent() })
    local texts = boxTexts(box)
    T.truthy(string.find(texts[#texts], a .. me, 1, true), "any other accent: the accent")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a mention's glow fades with its line (the game fades lines with no redraw)", function()
    local _, box = daylight()
    local Chat = stub.chatModule.Chat
    said(ChatFrame1, "is " .. UnitName("player") .. " coming?", "CHAT_MSG_GUILD", 1)
    stub.Advance(5)   -- past the new line's ease in
    box:FakeRefresh()
    local glow
    for _, r in ipairs({ box.FontStringContainer:GetRegions() }) do
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

T.test("chat daylight: a mention on the row past the top is cut off with its line", function()
    local _, box = daylight()
    said(ChatFrame1, "is " .. UnitName("player") .. " coming?", "CHAT_MSG_GUILD", 1)
    box:FakeRefresh()
    -- Push the mention up to the game's extra row, laid out above the box's top.
    for i = 1, box.fakeRows - 1 do said(ChatFrame1, "filler " .. i, "CHAT_MSG_GUILD", 100 + i) end
    stub.Advance(5)
    box:FakeRefresh()
    local top = box.visibleLines[box.fakeRows]
    T.truthy(top and top:IsShown() and string.find(top:GetText() or "", "coming", 1, true), "the mention sits on the top row")
    local glow
    for _, holder in ipairs({ box, box.FontStringContainer }) do
        for _, r in ipairs({ holder:GetRegions() }) do
            if r.__texture == "Interface\\Buttons\\WHITE8X8" and r:IsShown() then glow = r end
        end
    end
    T.truthy(glow, "its glow is drawn")
    -- The line is clipped by the game's container; a glow outside it showed as a
    -- bar floating over the game world above the chat.
    T.eq(glow:GetParent(), top:GetParent(), "inside the same clipping frame as its line")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: group lines get role icons and no whisper or invite links", function()
    local invited
    local _, box = daylight(function()
        _G.C_PartyInfo = _G.C_PartyInfo or {}
        _G.C_PartyInfo.InviteUnit = function(n) invited = n end
    end)
    channelLine(ChatFrame1, "LF2M SFM need tank and healer", "Torvik", 1, "LookingForGroup")
    local text = boxTexts(box)[1]
    T.isnil(string.find(text, "daylightchat:", 1, true), "no links of ours on the line")
    -- Daylight UI's own role art (Media/roles.png), inline as a texture.
    local _, icons = string.gsub(text, "|T[^|]-roles%.png", "")
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

T.test("chat: leader tags use native titles only on non-Latin clients", function()
    login()
    local Tags = stub.chatModule.Tags
    local savedLetters = DaylightUI:Get("Chat", "tagLetters")
    local savedOwn = {}
    for kind, text in pairs(Tags.own) do savedOwn[kind] = text end
    local lines = { party = "|Hchannel:PARTY|h[Party]|h Ann: hi", raid = "|Hchannel:RAID|h[Raid]|h Ann: hi",
                    instance = "|Hchannel:INSTANCE_CHAT|h[Instance]|h Ann: hi" }
    local events = { "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT_LEADER" }
    local kinds = { "party", "raid", "instance" }
    local get = function(kind, event) return Tags.Shorten(lines[kind], event) end
    local standard = { party = "PL", raid = "RL", instance = "IL" }
    local saved, names = {}, { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "CHAT_MSG_RAID_WARNING",
        "CHAT_WHISPER_INFORM_GET", "CHAT_SAY_GET" }
    for _, name in ipairs(names) do saved[name] = _G[name] end

    local function restore()
        for _, name in ipairs(names) do _G[name] = saved[name] end
        Tags.own = {}
        for kind, text in pairs(savedOwn) do Tags.own[kind] = text end
        DaylightUI:Set("Chat", "tagLetters", savedLetters or "native")
        stub.RunTimers()
        Tags.ResetDefaults()
    end

    local ok, err = pcall(function()
        local function set(t) for name, value in pairs(t) do _G[name] = value end; Tags.ResetDefaults() end
        local function expected(kind) return "|h[" .. standard[kind] .. "]|h" end

        -- The existing English letters and a custom ASCII parent stay exactly as before.
        for i, kind in ipairs(kinds) do T.truthy(get(kind, events[i]):find(expected(kind), 1, true), "standard leader tag") end
        Tags.SetOwn("party", "Grp")
        T.truthy(get("party", events[1]):find("|h[GrpL]|h", 1, true), "a custom ASCII parent still takes L")
        Tags.SetOwn("party", "")
        Tags.ResetDefaults()

        -- Latin words in native mode are still shortened to the same English letters.
        Tags.Apply({ shortTags = true, tagLetters = "native" })
        set({ CHAT_MSG_SAY = "Decir", CHAT_MSG_YELL = "Gritar", WHISPER = "Susurrar", CHAT_MSG_PARTY = "Grupo",
            CHAT_MSG_PARTY_LEADER = "Lider de grupo", CHAT_MSG_RAID = "Banda", CHAT_MSG_GUILD = "Hermandad",
            CHAT_MSG_OFFICER = "Oficial", CHAT_MSG_INSTANCE_CHAT = "Estancia", CHAT_MSG_RAID_WARNING = "Aviso de la banda",
            CHAT_WHISPER_INFORM_GET = "A %s: ", CHAT_SAY_GET = "%s dice: " })
        T.eq(Tags.Default("party"), "G", "Hermandad takes H, so Grupo takes G")
        T.truthy(get("party", events[1]):find("|h[GL]|h", 1, true), "Latin native words still take L")
        restore()

        -- Non-Latin game words give the title after the parent word: never the parent alone.
        set({ CHAT_MSG_PARTY = "小队", CHAT_MSG_PARTY_LEADER = "小队队长",
              CHAT_MSG_RAID = "团队", CHAT_MSG_RAID_LEADER = "团队领袖",
              CHAT_MSG_INSTANCE_CHAT = "副本", CHAT_MSG_INSTANCE_CHAT_LEADER = "副本向导" })
        T.truthy(get("party", events[1]):find("|h[队长]|h", 1, true), "Chinese party leader")
        T.truthy(get("raid", events[2]):find("|h[领袖]|h", 1, true), "Chinese raid leader")
        T.truthy(get("instance", events[3]):find("|h[向导]|h", 1, true), "Chinese instance leader")

        -- Leader tags are cached until ResetDefaults().
        _G.CHAT_MSG_PARTY_LEADER = "小队团长"
        T.truthy(get("party", events[1]):find("|h[队长]|h", 1, true), "cached leader tag stays until ResetDefaults")
        Tags.ResetDefaults()
        T.truthy(get("party", events[1]):find("|h[团长]|h", 1, true), "ResetDefaults clears cached leader tags")

        -- Traditional Chinese uses the same rule.
        set({ CHAT_MSG_PARTY = "隊伍", CHAT_MSG_PARTY_LEADER = "隊伍隊長" })
        T.truthy(get("party", events[1]):find("|h[隊長]|h", 1, true), "Traditional Chinese party leader")

        -- A non-Latin custom parent is not a Latin override, so the localized title still wins.
        set({ CHAT_MSG_PARTY = "小队", CHAT_MSG_PARTY_LEADER = "小队队长" })
        Tags.SetOwn("party", "队")
        Tags.ResetDefaults()
        T.truthy(get("party", events[1]):find("|h[队长]|h", 1, true), "a non-Latin custom parent keeps the native title")
        Tags.SetOwn("party", "Grp")
        Tags.ResetDefaults()
        T.truthy(get("party", events[1]):find("|h[GrpL]|h", 1, true), "a custom ASCII parent on a non-Latin client still takes L")
        Tags.SetOwn("party", "")
        Tags.ResetDefaults()
        restore()

        -- A leader word that does not start with the parent word must not be truncated.
        set({ CHAT_MSG_PARTY = "Группа", CHAT_MSG_PARTY_LEADER = "Лидер группы" })
        T.truthy(get("party", events[1]):find("|h[ГL]|h", 1, true), "a non-prefix leader falls back to L")

        -- Two leaders with the same extracted title neither uses it.
        set({ CHAT_MSG_PARTY = "파티", CHAT_MSG_PARTY_LEADER = "파티장", CHAT_MSG_RAID = "공격대",
            CHAT_MSG_RAID_LEADER = "공격대장" })
        T.truthy(get("party", events[1]):find("|h[파L]|h", 1, true), "a duplicate party title falls back to L")
        T.truthy(get("raid", events[2]):find("|h[공L]|h", 1, true), "a duplicate raid title falls back to L")

        -- The instance fallback globals work when the CHAT_MSG constants are absent.
        set({ CHAT_MSG_INSTANCE_CHAT = nil, CHAT_MSG_INSTANCE_CHAT_LEADER = nil,
            INSTANCE_CHAT = "副本", INSTANCE_CHAT_LEADER = "副本向导" })
        T.truthy(get("instance", events[3]):find("|h[向导]|h", 1, true), "instance leader fallback globals")
        restore()

        -- Back to English letters restores the original tags.
        Tags.Apply({ shortTags = true, tagLetters = "english" })
        for i, kind in ipairs(kinds) do T.truthy(get(kind, events[i]):find(expected(kind), 1, true), "English letters again") end
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end)

    restore()
    if not ok then error(err, 0) end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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

-- The short tags are set in the chat options, for the whole chat; a tab's Show window
-- only holds switches and colors.
T.test("chat daylight: the short tags page has a box per chat kind and channel, a tab's Show has none", function()
    daylight()
    local Tabs, Filter, Tags = stub.chatModule.Tabs, stub.chatModule.Filter, stub.chatModule.Tags
    local list = _G.GetChannelList
    _G.GetChannelList = function() return 1, "General", false, 5, "Heroes", false end
    Tabs.ShowMenu(UIParent, 2)
    for _, b in ipairs(Filter.Rows()) do T.isnil(b.tag, "no tag box in a tab's Show window") end
    Filter.Close()
    -- The options row.
    local item
    for _, page in ipairs(stub.chatModule.OPTIONS.pages) do
        for _, card in ipairs(page.groups or {}) do
            for _, it in ipairs(card.items) do if it.label == "Your own short tags" then item = it end end
        end
    end
    T.truthy(item, "the options have the row")
    local row = CreateFrame("Frame")
    item.build(row); item.update(row)
    local boxes = {}
    for side = 1, 2 do
        for _, line in ipairs(row.columns[side]) do
            if line:IsShown() then boxes[line.kind] = line end
        end
    end
    T.truthy(boxes["general"] and boxes["ch:heroes"], "a box for each channel")
    T.eq(boxes["general"].box.hint:GetText(), "G", "the box shows the standard tag until you type")
    T.eq(boxes["ch:heroes"].box.hint:GetText(), "5", "a channel with no standard tag shows its number")
    T.eq(boxes["guild"].box.hint:GetText(), "G", "a kind of chat has one too")
    T.isnil(boxes["channel"], "Other channels are many channels: no one tag")
    T.isnil(boxes["emote"], "emotes have no tag to change")
    local box = boxes["ch:heroes"].box
    box:SetText("HE")
    box:GetScript("OnTextChanged")(box, true)
    T.eq(Tags.Own("ch:heroes"), "HE", "typing sets it")
    box:SetText("")
    box:GetScript("OnTextChanged")(box, false)
    T.eq(Tags.Own("ch:heroes"), "HE", "only typing does")
    item.update(row)
    T.eq(box:GetText(), "HE", "listed again it shows your tag")
    T.truthy(item.hidden(function() return false end), "hidden with Short tags off")
    T.falsy(item.hidden(function() return true end), "shown with Short tags on")
    Tags.SetOwn("ch:heroes", "")
    _G.GetChannelList = list
end)

-- A sent whisper's tag is the word the game puts before the name; a whole phrase is too long for one.
T.test("chat daylight: the sent-whisper tag falls back to To when the game's word is longer than a few letters", function()
    daylight()
    local Tags = stub.chatModule.Tags
    local old = _G.CHAT_WHISPER_INFORM_GET
    DaylightUI:Set("Chat", "tagLetters", "native")
    stub.RunTimers()
    local chinese = "你悄悄地对%s:"   -- the whole phrase before the name on a Chinese client
    for fmt, want in pairs({ ["A %s:"] = "A", ["To %s:"] = "To", ["An %s:"] = "An", [chinese] = "To" }) do
        _G.CHAT_WHISPER_INFORM_GET = fmt
        Tags.ResetDefaults()
        T.eq(Tags.Default("to"), want, fmt)
    end
    _G.CHAT_WHISPER_INFORM_GET = old
    Tags.ResetDefaults()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The letters of the short tags: English ones, or the game's words in the player's language.
T.test("chat daylight: Tag letters starts in the player's language on a new profile, can be switched, and its boxes show a tooltip", function()
    daylight()
    local Tags = stub.chatModule.Tags
    T.eq(Tags.letters, "native", "a new profile starts on the player's language")
    local item
    for _, page in ipairs(stub.chatModule.OPTIONS.pages) do
        for _, card in ipairs(page.groups or {}) do
            for _, it in ipairs(card.items) do if it.key == "tagLetters" then item = it end end
        end
    end
    T.truthy(item, "the options have the drop-down")
    T.deq(item.order, { "english", "native" })
    for _, k in ipairs(item.order) do T.truthy(item.values[k], "a label for " .. k) end
    T.truthy(item.disabled(function() return false end), "off with Short tags off")
    T.falsy(item.disabled(function() return true end), "on with Short tags on")
    local old = { CHAT_MSG_SAY = _G.CHAT_MSG_SAY }
    _G.CHAT_MSG_SAY = "Decir"
    DaylightUI:Set("Chat", "tagLetters", "native")
    stub.RunTimers()
    T.eq(Tags.letters, "native", "a change reaches the tags at once")
    T.eq(Tags.Default("say"), "D", "the game's word, in the player's language")
    DaylightUI:Set("Chat", "tagLetters", "english")
    stub.RunTimers()
    T.eq(Tags.Default("say"), "S", "back to the English letters")
    _G.CHAT_MSG_SAY = old.CHAT_MSG_SAY
    -- The tooltip on a tag box shows (it was only filled before).
    local tip = GameTooltip
    local shown = false
    local owned
    GameTooltip = { SetOwner = function(_, o) owned = o end, Show = function() shown = true end, Hide = function() end,
                    IsOwned = function() return true end }
    local tips = DaylightUI.Tips
    local saved = { Title = tips.Title, Text = tips.Text, Flush = tips.Flush, Clear = tips.Clear }
    tips.Title, tips.Text, tips.Flush, tips.Clear = function() end, function() end, function() end, function() end
    local tagItem
    for _, page in ipairs(stub.chatModule.OPTIONS.pages) do
        for _, card in ipairs(page.groups or {}) do
            for _, it in ipairs(card.items) do if it.label == "Your own short tags" then tagItem = it end end
        end
    end
    local row = CreateFrame("Frame")
    tagItem.build(row); tagItem.update(row)
    local line
    for side = 1, 2 do for _, l in ipairs(row.columns[side]) do if l:IsShown() and not line then line = l end end end
    T.truthy(line, "a tag box")
    line.box:GetScript("OnEnter")(line.box)
    T.truthy(shown, "its tooltip is shown, not only filled")
    GameTooltip = tip
    tips.Title, tips.Text, tips.Flush, tips.Clear = saved.Title, saved.Text, saved.Flush, saved.Clear
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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

-- The game's own channel id names a world channel, whatever the language calls it.
T.test("chat daylight: world channels are known by the game's id, not their name", function()
    daylight()
    DaylightUI:Set("Chat", "tagLetters", "english")
    stub.RunTimers()
    local CH = stub.chatModule
    local Kinds, Tags = CH.Kinds, CH.Tags
    local ids = { DefensaLocal = 22, BuscarGrupo = 26, ["Comercio local"] = 46, Comercio = 2, ["General: Vallefresno"] = 1 }
    local old = _G.C_ChatInfo
    _G.C_ChatInfo = { GetChannelInfoFromIdentifier = function(n) return ids[n] and { zoneChannelID = ids[n] } or nil end }
    Kinds.ChannelsChanged()
    T.eq(Kinds.OfChannel("DefensaLocal"), "defense", "Spanish Local Defense")
    T.eq(Kinds.OfChannel("Comercio local - Ventormenta"), Kinds.TRADE_LOCAL, "Spanish Trade (Local)")
    T.eq(Kinds.OfChannel("General: Vallefresno"), "general", "a colon zone")
    T.eq(Kinds.OfChannel("BuscarGrupo"), "lfg", "Spanish Looking For Group")
    T.eq(Tags.Standard("BuscarGrupo", 5), "LFG")
    T.eq(Tags.Standard("DefensaLocal", 3), "LD", "its tag, not the bare number")
    T.eq(Tags.Standard("Comercio local", 4), "TL")
    T.eq(Tags.Standard("Comercio", 2), "T")
    -- World Defense and Newcomer have no id and share a kind with Local Defense and
    -- General, but keep their own tags.
    T.eq(Tags.Standard("WorldDefense", 7), "WD")
    T.eq(Tags.Standard("NewcomerChat", 8), "N")
    -- The game can't say: the names still work, in any case.
    _G.C_ChatInfo = nil
    Kinds.ChannelsChanged()
    T.eq(Kinds.OfChannel("DefensaLocal"), "defense", "by name without the game's help")
    T.eq(Tags.Standard("DefensaLocal", 3), "LD")
    T.eq(Tags.Standard("Comercio local", 4), "TL", "Trade (Local) in Spanish, by name")
    T.eq(Tags.Standard("WorldDefense", 7), "WD", "World Defense by name")
    T.eq(Tags.Standard("NewcomerChat", 8), "N", "Newcomer by name")
    -- A secret name is never sent to the game, which errors on one.
    local asked = false
    _G.C_ChatInfo = { GetChannelInfoFromIdentifier = function() asked = true end }
    local name = stub.Secret("Comercio")
    Kinds.ChannelsChanged()
    T.eq(Tags.OfName(name), nil)
    T.eq(asked, false, "the game was not asked about a secret name")
    _G.C_ChatInfo = old
    Kinds.ChannelsChanged()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- In the player's language the letters come from the name the game gives the channel.
T.test("chat daylight: world channels take the letters of their own name when asked for", function()
    daylight()
    local CH = stub.chatModule
    local Kinds, Tags = CH.Kinds, CH.Tags
    local ids = { DefensaLocal = 22, BuscarGrupo = 26, ["Comercio local"] = 46, Comercio = 2, ["General: Vallefresno"] = 1 }
    local old = _G.C_ChatInfo
    _G.C_ChatInfo = { GetChannelInfoFromIdentifier = function(n) return ids[n] and { zoneChannelID = ids[n] } or nil end }
    Kinds.ChannelsChanged()
    Tags.Apply({ shortTags = true, tagLetters = "native" })
    T.eq(Tags.Standard("DefensaLocal", 3), "DL", "its tag, not the bare number: the name's letters")
    T.eq(Tags.Standard("Comercio local", 4), "CL")
    T.eq(Tags.Standard("Comercio", 2), "C")
    T.eq(Tags.Standard("BuscarGrupo", 5), "BG")
    T.eq(Tags.Standard("General: Vallefresno", 1), "G")
    T.eq(Tags.Initials("Defensa de la ciudad"), "DC", "short words left out")
    T.eq(Tags.Initials("LocalDefense"), "LD")
    T.eq(Tags.Initials("Trade (Local)"), "TL")
    T.eq(Tags.Initials("公会"), "公", "the first character of a Chinese name")
    -- Back to the English letters, which is what the setting starts as.
    Tags.Apply({ shortTags = true })
    T.eq(Tags.Standard("DefensaLocal", 3), "LD", "English letters again")
    T.eq(Tags.Standard("Comercio", 2), "T")
    _G.C_ChatInfo = old
    Kinds.ChannelsChanged()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- In the player's language a chat kind's tag comes from the game's own word for it, the first in
-- the order keeping the short one when two start the same.
T.test("chat daylight: chat kinds take their default tag from the game's words when asked for", function()
    daylight()
    local Tags = stub.chatModule.Tags
    Tags.Apply({ shortTags = true, tagLetters = "native" })
    local saved = {}
    local names = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_RAID", "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_RAID_WARNING", "CHAT_WHISPER_INFORM_GET", "CHAT_SAY_GET" }
    for _, n in ipairs(names) do saved[n] = _G[n] end
    local function words(t) for n, v in pairs(t) do _G[n] = v end; Tags.ResetDefaults() end
    -- Spanish, as the game gives it.
    words({ CHAT_MSG_SAY = "Decir", CHAT_MSG_YELL = "Gritar", WHISPER = "Susurrar", CHAT_MSG_PARTY = "Grupo",
        CHAT_MSG_RAID = "Banda", CHAT_MSG_GUILD = "Hermandad", CHAT_MSG_OFFICER = "Oficial",
        CHAT_MSG_INSTANCE_CHAT = "Estancia", CHAT_MSG_RAID_WARNING = "Aviso de la banda",
        CHAT_WHISPER_INFORM_GET = "A %s: ", CHAT_SAY_GET = "%s dice: " })
    local got = {}
    for _, k in ipairs({ "guild", "party", "raid", "say", "whisper", "yell", "instance", "officer", "warning", "bnet", "to" }) do
        got[#got + 1] = Tags.Default(k)
    end
    T.eq(table.concat(got, " "), "H G B D S Gr E O AB S A", "Spanish")
    T.eq(Tags.Shorten("|Hplayer:Bob|h[Bob]|h dice: hola", "CHAT_MSG_SAY"), "[D] |Hplayer:Bob|h[Bob]|h: hola", "a say line")
    -- English gives the letters it always had.
    words({ CHAT_MSG_SAY = "Say", CHAT_MSG_YELL = "Yell", WHISPER = "Whisper", CHAT_MSG_PARTY = "Party",
        CHAT_MSG_RAID = "Raid", CHAT_MSG_GUILD = "Guild", CHAT_MSG_OFFICER = "Officer",
        CHAT_MSG_INSTANCE_CHAT = "Instance", CHAT_MSG_RAID_WARNING = "Raid Warning",
        CHAT_WHISPER_INFORM_GET = "To %s: " })
    got = {}
    for _, k in ipairs({ "guild", "party", "raid", "say", "whisper", "yell", "instance", "officer", "warning", "bnet", "to" }) do
        got[#got + 1] = Tags.Default(k)
    end
    T.eq(table.concat(got, " "), "G P R S W Y I O RW W To", "English")
    -- Nothing from the game: the English letters.
    for _, n in ipairs(names) do _G[n] = nil end
    Tags.ResetDefaults()
    T.eq(Tags.Default("say"), "S")
    T.eq(Tags.Default("warning"), "RW")
    T.eq(Tags.Default("to"), "To")
    for _, n in ipairs(names) do _G[n] = saved[n] end
    -- In English letters the game's words don't matter: the letters it always had.
    Tags.Apply({ shortTags = true })
    words({ CHAT_MSG_PARTY = "Grupo", CHAT_MSG_YELL = "Gritar", CHAT_WHISPER_INFORM_GET = "A %s: " })
    T.eq(Tags.Default("party"), "P", "English letters, in a Spanish client")
    T.eq(Tags.Default("yell"), "Y")
    T.eq(Tags.Default("to"), "To")
    for _, n in ipairs(names) do _G[n] = saved[n] end
    Tags.ResetDefaults()
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

-- A player missed their Battle.net friend's whispers on a tab with Whispers on,
-- and kept seeing them on one with Whispers off: Battle.net whispers had a switch
-- of their own. One Whispers switch covers both now.
T.test("chat daylight: one Whispers switch covers Battle.net whispers too; saved tabs keep whispers if either was on", function()
    local Box, box = daylight(function()
        ChatTypeInfo.WHISPER = { id = 7, r = 1, g = 0.5, b = 1 }
        ChatTypeInfo.BN_WHISPER = { id = 9, r = 0, g = 1, b = 1 }
    end)
    local CH = stub.chatModule
    local Kinds = CH.Kinds
    DaylightUI:Set("Chat", "tabs", {
        { name = "Both", kinds = { whisper = true, bnet = false }, v = 8 },
        { name = "Bnet only", kinds = { bnet = true }, v = 8 },
        { name = "All, whispers off", all = true, kinds = { whisper = false }, v = 8 },
        { name = "All, both off", all = true, kinds = { whisper = false, bnet = false }, v = 8 },
        { name = "Old", kinds = { whisper = true }, v = 2 },
        { name = "None", kinds = { party = true }, v = 2 },
        { name = "Old all", all = true, v = 2 },
    })
    stub.RunTimers()
    local tabs = Box.Tabs()
    T.eq(tabs[1].kinds.whisper, true, "on and off: on")
    T.eq(tabs[2].kinds.whisper, true, "only Battle.net on: whispers on")
    T.isnil(tabs[3].kinds.whisper, "an everything tab with Battle.net still on shows whispers")
    T.eq(tabs[4].kinds.whisper, false, "both off: off")
    T.eq(tabs[5].kinds.whisper, true, "a tab saved long ago keeps its whispers")
    T.falsy(tabs[6].kinds.whisper, "nothing it didn't show")
    T.falsy(tabs[6].kinds.instance, "an older split isn't run again: instance off stays off")
    T.isnil(tabs[7].kinds and tabs[7].kinds.whisper, "an old everything tab shows them all")
    for i, tab in ipairs(tabs) do
        T.isnil(tab.kinds and tab.kinds.bnet, "no Battle.net switch left on tab " .. i)
        T.eq(tab.v, Kinds.VERSION)
    end
    T.truthy(Kinds.Shows(tabs[1], "bnet"), "Whispers on: Battle.net whispers show")
    T.falsy(Kinds.Shows(tabs[4], "bnet"), "Whispers off: they don't")
    -- A Battle.net whisper lands where Whispers is on, and only there.
    DaylightUI:Set("Chat", "tabs", {
        { name = "Gen", all = true, kinds = { whisper = false }, v = Kinds.VERSION },
        { name = "G/I", kinds = { whisper = true, say = true }, v = Kinds.VERSION },
    })
    stub.RunTimers()
    Box.Pick(1)
    ChatFrame1:AddMessage("[Kira]: hey", 0, 1, 1, 9, nil, nil, "CHAT_MSG_BN_WHISPER", { "hey", "Kira", n = 14 })
    T.eq(#boxTexts(box), 0, "not on the tab with Whispers off")
    Box.Pick(2)
    T.eq(table.concat(boxTexts(box), "|"), "[Kira]: hey", "on the tab with Whispers on")
    CH.Filter.Open(2)
    local whisperRow, bnetRow
    for _, b in ipairs(CH.Filter.Rows()) do
        if b.kind == "whisper" then whisperRow = b end
        if b.kind == "bnet" then bnetRow = b end
    end
    T.truthy(whisperRow, "the Whispers switch")
    T.falsy(bnetRow, "no Battle.net whispers row")
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

T.test("chat daylight: line spacing spreads the box's lines, and 0 is the game's own", function()
    local Box, box = daylight()
    local DUI = DaylightUI
    local gap
    box.SetSpacing = function(_, v) gap = v end
    Box.Font()
    T.eq(gap, 0, "untouched: the game's own spacing")
    DUI:Set("Chat", "lineSpacing", 6)
    stub.RunTimers()
    T.eq(gap, 6, "the chosen pixels")
    DUI:Set("Chat", "lineSpacing", -3)
    stub.RunTimers()
    T.eq(gap, 0, "never negative")
    DUI:Set("Chat", "lineSpacing", 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: messages line up on the left, or the right when asked", function()
    local Box, box = daylight()
    local DUI = DaylightUI
    Box.Font()
    T.eq(box:GetJustifyH(), "LEFT", "left by default")
    DUI:Set("Chat", "align", "right")
    stub.RunTimers()
    T.eq(box:GetJustifyH(), "RIGHT", "right once picked")
    DUI:Set("Chat", "align", "left")
    stub.RunTimers()
    T.eq(box:GetJustifyH(), "LEFT")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a combat log tab shows the game's combat log in the chat's place", function()
    local selected
    local Box, box = daylight(function()
        _G.FCFDock_SelectWindow = function(_, cf) selected = cf end
        _G.FCFDock_GetSelectedWindow = function() return ChatFrame1 end
    end)
    local Tabs = stub.chatModule.Tabs
    local i = Tabs.Add(true)
    stub.RunTimers()
    ChatFrame2:Hide()
    Box.Pick(i)
    T.isnil(selected, "shown in place, never selected in the dock")
    T.truthy(ChatFrame2:IsShown(), "the combat log shows")
    T.eq(ChatFrame2:GetAlpha(), 1, "and seen")
    T.falsy(box:IsShown(), "our list away")
    stub.chatModule.Chat.Pass()
    T.eq(ChatFrame2:GetAlpha(), 1, "the watcher leaves it seen")
    ChatFrame2:Hide()   -- the dock hides windows it hasn't selected as it lays out its tabs
    stub.chatModule.Chat.Pass()
    T.truthy(ChatFrame2:IsShown(), "the watcher shows it back")
    Box.Pick(1)
    T.isnil(selected)
    T.falsy(ChatFrame2:IsShown(), "put away")
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
    t.input:SetFocus()
    t.input:SetText("omw")
    t.input:GetScript("OnEnterPressed")(t.input)
    T.eq(sent and sent[1], "omw")
    T.eq(sent[2], "WHISPER")
    T.eq(sent[3], "Lephoque")
    T.falsy(t.input:HasFocus(), "sent: the keyboard goes back to the game, as the game's own chat box")
    local keys = _G.DaylightUIChatTalk.keys
    keys:GetScript("OnKeyDown")(keys, "ENTER")
    T.truthy(t.input:HasFocus(), "Enter with the card open types to them again, never to the main chat")
    t.input:GetScript("OnEnterPressed")(t.input)
    T.falsy(t.input:HasFocus(), "an empty Enter lets go too")
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

-- A Whisper button in Daylight UI's own windows (friends, group finder) opens the
-- card with that person. Opening the game's chat box from addon code left it
-- tainted, and a later reply to a hidden name errored every time it opened.
T.test("chat whispers: a Whisper button elsewhere opens the card with that person, never the game's box", function()
    local sent, opened = {}, {}
    daylight(function()
        _G.C_ChatInfo = _G.C_ChatInfo or {}
        _G.C_ChatInfo.SendChatMessage = function(text, kind, _, to) sent[#sent + 1] = { text, kind, to } end
        _G.BNSendWhisper = function(id, text) sent[#sent + 1] = { text, "BN", id } end
    end)
    local CH = stub.chatModule
    for _, k in ipairs({ "OpenChat", "SendTell", "SendBNetTell" }) do
        _G.ChatFrameUtil[k] = function() opened[#opened + 1] = k end
    end
    DaylightUI.Pad.Whisper({ name = "Arthas" })
    T.eq(#opened, 0, "the game's chat box stays shut")
    T.truthy(CH.Convo.Showing("w:Arthas"), "the card opens with Arthas")
    local t = CH.Convo.Thread()
    T.truthy(t.input:HasFocus(), "ready to type")
    t.input:SetText("lfg?")
    t.input:GetScript("OnEnterPressed")(t.input)
    T.deq(sent[#sent], { "lfg?", "WHISPER", "Arthas" }, "sent to Arthas")
    -- A Battle.net friend: their own conversation, by account.
    DaylightUI.Pad.Whisper({ bn = 7, name = "Jaina" })
    T.truthy(CH.Convo.Showing("bn:7"), "a Battle.net friend's card")
    t.input:SetText("hey")
    t.input:GetScript("OnEnterPressed")(t.input)
    T.deq(sent[#sent], { "hey", "BN", 7 })
    -- Someone already talking to you: the conversation you have, lines and all.
    whisper("hi", "Lephoque")
    DaylightUI.Pad.Whisper({ name = "Lephoque" })
    T.truthy(CH.Convo.Showing("w:Lephoque"), "the conversation you already have")
    T.eq(#CH.Talk.Get("w:Lephoque").msgs, 1, "with its line")
    -- No card with whispers kept in the chat only: Daylight UI's small box asks.
    CH.Convo.Close()
    DaylightUI:Set("Chat", "whispersIn", "chat")
    stub.RunTimers()
    local W = DaylightUI.Widgets
    local prompt, asked = W.Prompt, nil
    W.Prompt = function(text) asked = text end
    DaylightUI.Pad.Whisper({ name = "Thrall" })
    W.Prompt = prompt
    T.truthy(asked and asked:find("Thrall", 1, true), "the small box asks instead")
    T.falsy(CH.Convo.Showing("w:Thrall"))
    T.eq(#opened, 0, "still never the game's box")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Only a Whisper action means "I want to write to them". Opening a conversation to
-- read it (a tile, the preview, Pop out from the hub) leaves the keyboard on spells.
T.test("chat whispers: only a Whisper button types; a tile, the preview or Pop out just opens", function()
    daylight()
    local CH = stub.chatModule
    whisper("hi", "Lephoque")
    local t
    local function typing() t = CH.Convo.Thread(); return t and t.input:HasFocus() end
    CH.Convo.Toggle("w:Lephoque")                          -- a tile's click
    T.truthy(CH.Convo.Showing("w:Lephoque"))
    T.falsy(typing(), "a tile opens the card without typing")
    CH.Convo.Close()
    stub.RunTimers()
    CH.Convo.Open("w:Lephoque")                            -- the preview's click
    T.falsy(typing(), "the preview opens it without typing")
    CH.Convo.Close()
    stub.RunTimers()
    CH.Hub.Open("w:Lephoque")
    CH.Thread.LINKS.pop.click({ c = "w:Lephoque" })        -- Pop out
    T.truthy(CH.Convo.Showing("w:Lephoque"))
    T.falsy(typing(), "Pop out opens it without typing")
    -- Already open, then Whisper from the friends list: it types now.
    DaylightUI.Pad.Whisper({ name = "Lephoque" })
    T.truthy(typing(), "a Whisper button types to them")
    CH.Convo.Close()
    stub.RunTimers()
    DaylightUI.Pad.Whisper({ name = "Arthas" })
    T.truthy(typing(), "and from a closed card")
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

    T.eq(Menu.Tip(), "Chat menu", "short: what it does is in the line under it")
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

T.test("chat daylight: a header icon's tooltip shows at once, with its name and what it does", function()
    local Box = daylight()
    local Tips = DaylightUI.Tips
    local tip = fakeTooltip()
    function tip:Show() self.shown = true end
    function tip:IsOwned(o) return self.owner == o end
    local saved = { Title = Tips.Title, Text = Tips.Text, Flush = Tips.Flush }
    local got
    Tips.Title = function(t) got = { title = t } end
    Tips.Text = function(t) if got then got.desc = t end end
    Tips.Flush = function() end
    for _, name in ipairs({ "whispers", "voice", "menu", "copy", "lock", "options" }) do
        local icon = Box.main.icons[name]
        if icon then
            got = nil
            icon.IsMouseOver = function() return true end
            icon:GetScript("OnEnter")(icon)
            T.falsy(got, name .. ": waits for the mouse to rest, as every icon button does")
            stub.RunTimers()
            T.truthy(got and got.title, name .. ": has a name")
            T.truthy(got.desc, name .. ": and a line on what it does")
            T.eq(tip.owner, icon, name .. ": on the icon")
            icon:GetScript("OnLeave")(icon)
        end
    end
    T.truthy(Box.main.icons.copy, "the copy icon exists")
    Tips.Title, Tips.Text, Tips.Flush = saved.Title, saved.Text, saved.Flush
    _G.GameTooltip = nil
end)

T.test("chat daylight: the \"+\" tab says what it adds and sits a little apart from the tabs", function()
    local Box = daylight()
    local plus = Box.main.plus
    local tip = fakeTooltip()
    function tip:Show() self.shown = true end
    local Tips = DaylightUI.Tips
    local saved = { Title = Tips.Title, Text = Tips.Text, Hint = Tips.Hint, Flush = Tips.Flush }
    local words = {}
    Tips.Title = function(t) words[#words + 1] = t end
    Tips.Text = function(t) words[#words + 1] = t end
    Tips.Hint = function() end
    Tips.Flush = function() end
    plus:GetScript("OnEnter")(plus)
    Tips.Title, Tips.Text, Tips.Hint, Tips.Flush = saved.Title, saved.Text, saved.Hint, saved.Flush
    _G.GameTooltip = nil
    T.truthy(tip.shown, "the tooltip is shown, not only filled")
    T.eq(words[1], "New tab")
    T.eq(words[2], "Adds a chat tab, or a combat log tab.", "a line on what it adds")
    local last
    for _, b in ipairs(Box.main.buttons) do if b:IsShown() then last = b end end
    T.truthy(last, "a shown tab")
    local lastAt = select(4, last:GetPoint(1))
    local plusAt = select(4, plus:GetPoint(1))
    T.eq(plusAt - (lastAt + last:GetWidth()), Box.PLUS_GAP, "the gap before the plus")
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

-- A window pulled out of the dock before the Daylight box was on stays parked out of
-- sight, but in the IM chat style its invisible click-anywhere button still made its
-- own box the one you type in, and that box opened over the lines where the old
-- window sat.
T.test("chat box: a pulled-out window's typing box opens in the footer, and its click-anywhere is parked", function()
    local Box = daylight()
    local CH = stub.chatModule
    stub.RunTimers()
    CH.Chat.Pass()
    T.falsy(ChatFrame3.isDocked, "set up undocked")
    T.eq(select(2, ChatFrame3EditBox:GetPoint(1)), Box.Field(), "its box over the footer's field")
    T.falsy(ChatFrame3.clickAnywhereButton:IsMouseEnabled(), "its click-anywhere takes no clicks")
    T.falsy(ChatFrame1.clickAnywhereButton:IsMouseEnabled(), "nor the main window's")
    DaylightUI:Set("Chat", "style", "classic")
    stub.RunTimers()
    CH.Chat.Pass()
    T.eq(select(2, ChatFrame3EditBox:GetPoint(1)), ChatFrame3, "Classic: back under its own window")
    T.truthy(ChatFrame3.clickAnywhereButton:IsMouseEnabled(), "and its click-anywhere is the game's again")
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

-- Busy channels send many lines a second: the words' patterns are built once,
-- and again only when the words change.
T.test("chat daylight: alert patterns are built once, not for every line", function()
    local Box = daylight()
    local E = stub.chatModule.Extras
    said(ChatFrame1, "is " .. UnitName("player") .. " coming?", "CHAT_MSG_GUILD", 1)
    local first = E.AlertPatterns()
    said(ChatFrame1, "anyone seen " .. UnitName("player") .. "?", "CHAT_MSG_GUILD", 2)
    T.truthy(Box.Log()[#Box.Log()].alert, "still lights up")
    T.eq(E.AlertPatterns(), first, "the same patterns, not rebuilt")
    DaylightUI:Set("Chat", "alertWords", "onyxia, raid")
    T.truthy(E.AlertPatterns() ~= first, "rebuilt for new words")
    said(ChatFrame1, "Onyxia tonight", "CHAT_MSG_GUILD", 3)
    T.truthy(Box.Log()[#Box.Log()].alert, "a new word lights up")
    DaylightUI:Set("Chat", "alertWords", "")
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
    -- The click lands on the name's twin, whose hook tells the box a /who was asked.
    stub.chatModule.Links.NameClicked("player:Bob:7:CHANNEL:2")
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
    -- Through the tab's own scripts: moving it hides its button on this panel,
    -- which must not happen inside that button's OnDragStop.
    local over = Box.main.holder.IsMouseOver
    Box.main.holder.IsMouseOver = function() return true end
    local b = side.buttons[3]
    b:GetScript("OnDragStart")(b, "LeftButton")
    b:GetScript("OnDragStop")(b)
    Box.main.holder.IsMouseOver = over
    stub.RunTimers()
    T.falsy(Box.Tabs()[3].side, "let go over the main panel: it moves there")
    T.eq(Box.Picked(), 3, "picked there")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat second panel: its combat log tab brings the game's window there", function()
    local selected
    local Box, box = daylight(function()
        _G.FCFDock_SelectWindow = function(_, cf) selected = cf end
        _G.FCFDock_GetSelectedWindow = function() return ChatFrame1 end
    end)
    local CH = stub.chatModule
    local Tabs, side = CH.Tabs, Box.side
    Tabs.SetSide(4, true)
    local i = Tabs.Add(true, true)
    stub.RunTimers()
    Box.Pick(i)
    T.isnil(selected, "never selected in the dock")
    T.truthy(ChatFrame2:IsShown())
    T.eq(ChatFrame2:GetAlpha(), 1, "seen")
    T.eq(select(2, ChatFrame2:GetPoint(1)), side.area, "in the second panel's place")
    T.falsy(side.frame:IsShown(), "that panel's list away")
    T.truthy(box:IsShown(), "the main panel's stays")
    Box.Pick(2)
    T.truthy(ChatFrame2:IsShown(), "picking on the main panel leaves it")
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
        _G.FCFDock_GetSelectedWindow = function() return ChatFrame1 end
    end)
    local Tabs = stub.chatModule.Tabs
    Tabs.SetSide(4, true)
    local i = Tabs.Add(true, true)
    Box.Pick(i)
    Tabs.Remove(i)
    T.isnil(selected)
    T.falsy(ChatFrame2:IsShown())
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

T.test("chat border: the global style, then its own look on every panel", function()
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
    DUI:Set("Chat", "frameStyle.global", false)
    DUI:Set("Chat", "frameStyle.heavyBorder", false)
    DUI:Set("Chat", "frameStyle.borderPx", 3)
    stub.RunTimers()
    for name, s in pairs({ main = main, side = side, float = float }) do
        T.falsy(Style.IsHeavy(s), name .. ": a plain line")
        T.eq(Style.ShellLook(s).borderPx, 3, name .. ": its thickness")
    end
    DUI:Set("Chat", "frameStyle.borderAlpha", 0)
    stub.RunTimers()
    T.eq(main.border.LEFT.__vertex[4], 0, "no border")
    T.eq(side.border.LEFT.__vertex[4], 0)
    DUI:Set("Chat", "frameStyle.global", true)
    DUI:Set("Chat", "style", "classic")
    stub.RunTimers()
    T.truthy(main.opts.flat, "Classic on the global style: its thin line")
    T.eq(main.opts.borderPx, 1)
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
    T.eq(main.opts.borderColor, nil, "a color comes with the chat's own look")
    DUI:Set("Chat", "frameStyle.global", false)
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
    DUI:Set("Chat", "frameStyle.global", false)
    DUI:Set("Chat", "frameStyle.windowAlpha", 0.6)
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
    T.truthy(loot.kinds.opening and loot.kinds.currency, "loot and money brought theirs along")
    T.falsy(loot.kinds.tradeskill, "but not crafting, left out of every saved tab")
    T.falsy(loot.kinds.pvp, "nothing it didn't show")
    T.truthy(sys.kinds.pvp and sys.kinds.pet and sys.kinds.misc and sys.kinds.icons and sys.kinds.bnalert,
        "what went to System still shows there")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: crafting lines stay off the General and Loot tabs", function()
    local Box = daylight()
    local Kinds = stub.chatModule.Kinds
    local Tabs = stub.chatModule.Tabs
    local general, loot = Box.Tabs()[1], Box.Tabs()[4]
    T.truthy(general.all, "General is still an everything tab")
    T.falsy(Kinds.Shows(general, "tradeskill"), "no crafting lines on General")
    T.truthy(Kinds.Shows(general, "say") and Kinds.Shows(general, "loot"), "everything else stays")
    T.falsy(Kinds.Shows(loot, "tradeskill"), "nor on Loot")
    T.truthy(Kinds.Shows(loot, "loot"), "Loot still has loot")
    -- Switching crafting back on keeps General an everything tab.
    Tabs.SetKind(1, "tradeskill", true)
    stub.RunTimers()
    general = Box.Tabs()[1]
    T.truthy(general.all and Kinds.Shows(general, "tradeskill"), "back on, still everything")
    -- Switching one kind off from there leaves crafting on.
    Tabs.SetKind(1, "loot", false)
    stub.RunTimers()
    general = Box.Tabs()[1]
    T.truthy(general.kinds.tradeskill and not general.kinds.loot, "only loot went off")
    -- Everything on again shows every kind.
    DaylightUI:Set("Chat", "tabs", nil)
    stub.RunTimers()
    Tabs.SetKind(1, "all", true)
    stub.RunTimers()
    T.truthy(Kinds.Shows(Box.Tabs()[1], "tradeskill"), "Everything means everything")
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

T.test("chat on a controller: Classic whatever the setting, one hint bar: the game's own under the typing box", function()
    local Box = daylight()
    local Chat = stub.chatModule.Chat
    T.truthy(Box.On(), "the Daylight box, mouse and keyboard")
    _G.GamepadMode = { FrameControlsManager = { FrameShown = function() end, FrameHidden = function() end } }
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    DaylightUI.Fire("PadChanged")
    stub.RunTimers()
    T.falsy(Box.On(), "controller mode: the game's chat windows, skinned")
    T.falsy(DaylightUIChatBox:IsShown(), "the Daylight box steps aside")
    T.eq(DaylightUI:Get("Chat", "style"), "daylight", "the setting stays as picked")
    local eb, focused = ChatFrame1EditBox, true
    local had = eb.HasFocus
    eb.HasFocus = function() return focused end   -- the fake game's boxes never hold focus
    -- The game's chat footer (FloatingChatFrameMixin:CreateFooter): its legend is a
    -- child of the chat frame, hung under the edit box, shown on FocusGamepad, which
    -- every focus of the box brings (ChatFrameEditBoxMixin:OnEditFocusGained).
    local legend = CreateFrame("Frame", nil, ChatFrame1)
    legend:SetPoint("TOPLEFT", eb, "BOTTOMLEFT")
    legend:SetSize(300, 30)
    Chat.Input(0.016)
    T.truthy(legend:IsVisible() and legend:GetEffectiveAlpha() > 0, "the game's own bar shows under the box")
    T.eq(DaylightUI.Pad.taken, nil, "Daylight UI draws no second bar")
    T.falsy(DaylightUI.Pad.hints and DaylightUI.Pad.hints:IsShown(), "no Daylight UI hint bar over the box")
    for _, k in ipairs({ "PAD1", "PAD3", "PAD4", "PADLSHOULDER" }) do T.eq(stub.overrides[k], nil, k .. " stays the game's") end
    focused = false
    Chat.Input(0.016)
    legend:Hide()
    T.eq(DaylightUI.Pad.taken, nil, "done typing: nothing held")
    eb.HasFocus = had
    _G.GamepadMode, _G.InputUtil = nil, nil
    DaylightUI.Fire("PadChanged")
    stub.RunTimers()
    T.truthy(Box.On(), "controller mode off: the Daylight box again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat daylight: a level beside names the game has told us, only with the setting on", function()
    local Box, box = daylight(function()
        _G.GetNormalizedRealmName = function() return "Home" end
        _G.IsInGuild = function() return true end
        _G.GetNumGuildMembers = function() return 2 end
        _G.GetGuildRosterInfo = function(i)
            if i == 1 then return "Bram-Home", "Member", 1, 60 end
            return "Cass-Far", "Member", 1, 23
        end
    end)
    local plain = function(s) return (string.gsub(string.gsub(s, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")) end
    local function line(who, n) said(ChatFrame1, "|Hplayer:" .. who .. ":" .. n .. "|h[" .. who .. "]|h: hi", "CHAT_MSG_GUILD", n) end
    line("Bram", 1)
    T.falsy(plain(boxTexts(box)[box:GetNumMessages()]):find("[60]", 1, true), "off by default")
    DaylightUI:Set("Chat", "levels", true)
    stub.FireEvent("GUILD_ROSTER_UPDATE")
    line("Bram", 2)
    T.truthy(plain(boxTexts(box)[box:GetNumMessages()]):find("^%[60%] |Hplayer:Bram"), boxTexts(box)[box:GetNumMessages()])
    line("Cass-Far", 3)
    T.truthy(plain(boxTexts(box)[box:GetNumMessages()]):find("^%[23%] |Hplayer:Cass%-Far"), "another realm's name, by its full name")
    line("Stranger", 4)
    T.truthy(plain(boxTexts(box)[box:GetNumMessages()]):find("^|Hplayer:Stranger"), "never seen: no level")
    local realLevel, realIs = _G.UnitLevel, _G.UnitIsPlayer
    _G.UnitIsPlayer = function(u) return u == "target" or (realIs and realIs(u)) end
    _G.UnitFullName = function(u) if u == "target" then return "Stranger", nil end end
    _G.UnitLevel = function(u) if u == "target" then return 12 end return realLevel and realLevel(u) end
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    line("Stranger", 5)
    T.truthy(plain(boxTexts(box)[box:GetNumMessages()]):find("^%[12%] |Hplayer:Stranger"), "targeted once: known")
    _G.UnitLevel, _G.UnitIsPlayer, _G.UnitFullName = realLevel, realIs, nil
    _G.GetNormalizedRealmName, _G.IsInGuild, _G.GetNumGuildMembers, _G.GetGuildRosterInfo = nil, nil, nil, nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: another addon's channels on 1 to 4 move behind the world channels", function()
    -- The game's slots: an addon joined its own channels before the world ones.
    local slots = { "layer", "layer99d80872", "layer99fc0872", "layer99d20872",
        "General - Elwynn Forest", "Trade - City", "LocalDefense - Elwynn Forest", "Services", "LookingForGroup" }
    local zone = { General = 1, Trade = 2, LocalDefense = 22, Services = 42, LookingForGroup = 26 }
    local was = { _G.GetChannelList, _G.C_ChatInfo, _G.ChangeChatColor }
    _G.GetChannelList = function()
        local out = {}
        for id = 1, #slots do
            if slots[id] then out[#out + 1] = id; out[#out + 1] = slots[id]; out[#out + 1] = false end
        end
        return unpack(out)
    end
    local swaps = 0
    _G.C_ChatInfo = setmetatable({
        GetChannelInfoFromIdentifier = function(name)
            local base = string.match(name, "^(.-) %- ") or name
            return { name = name, zoneChannelID = zone[base] or 0 }
        end,
        SwapChatChannelsByChannelIndex = function(a, b)
            swaps = swaps + 1
            slots[a], slots[b] = slots[b], slots[a]
        end,
    }, { __index = was[2] })
    _G.ChangeChatColor = function() end
    local Kinds = stub.chatModule.Kinds
    stub.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    stub.FireEvent("CHANNEL_UI_UPDATE"); stub.RunTimers()
    T.eq(slots[1], "General - Elwynn Forest", "General back on 1")
    T.eq(slots[2], "Trade - City")
    T.eq(slots[3], "LocalDefense - Elwynn Forest")
    T.eq(slots[4], "Services")
    T.eq(slots[5], "LookingForGroup")
    T.eq(slots[6], "layer", "the addon's channels keep their own order after them")
    T.eq(slots[9], "layer99d20872")
    local done = swaps
    stub.FireEvent("CHANNEL_UI_UPDATE"); stub.RunTimers()
    T.eq(swaps, done, "already in order: nothing more")
    -- A player's own order is theirs with the switch off.
    slots[1], slots[6] = slots[6], slots[1]
    DaylightUI:Set("Chat", "worldChannelsFirst", false)
    stub.FireEvent("CHANNEL_UI_UPDATE"); stub.RunTimers()
    T.eq(slots[1], "layer", "switched off: left as it is")
    DaylightUI:Set("Chat", "worldChannelsFirst", true)
    slots = { "layer", "General - Elwynn Forest", "Trade - City" }
    stub.EnterCombat()
    stub.FireEvent("CHANNEL_UI_UPDATE"); stub.RunTimers()
    T.eq(slots[1], "layer", "not in a fight")
    stub.LeaveCombat(); stub.RunTimers()
    T.eq(slots[1], "General - Elwynn Forest", "after it")
    -- Later in the session the game joins LookingForGroup behind an addon's channel
    -- and announces it as 7: it stays 7, or /7 would talk in the addon's channel.
    stub.Advance(Kinds.WORLD_SETTLE + 1)
    slots = { "General - Elwynn Forest", "Trade - City", "OOC", "Services", "TradeLocal", "NRDT",
        "LookingForGroup" }
    stub.FireEvent("CHANNEL_UI_UPDATE"); stub.RunTimers()
    T.eq(slots[7], "LookingForGroup", "a channel joined after login keeps the number the game gave it")
    T.eq(slots[6], "NRDT", "and nothing else moves")
    -- A reload isn't a login: the numbers you've been typing all session stay.
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, true)
    stub.FireEvent("CHANNEL_UI_UPDATE"); stub.RunTimers()
    T.eq(slots[7], "LookingForGroup", "a reload moves nothing")
    T.truthy(Kinds.WorldFirst, "Kinds.WorldFirst exists")
    _G.GetChannelList, _G.C_ChatInfo, _G.ChangeChatColor = was[1], was[2], was[3]
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: every options page is valid", function()
    login()
    local n = 0
    for id, page in DaylightUI.Options.Pages() do
        if page.scope == "Chat" then
            local errors = DaylightUI.Options.ValidatePage(page)
            T.eq(#errors, 0, id .. ": " .. tostring(errors[1]))
            n = n + 1
        end
    end
    T.truthy(n > 0, "found the chat pages")
    T.falsy(stub.ChatContains("Options ("))
end)

T.test("chat daylight: a step of the watcher failing still keeps the game's window out of sight", function()
    local Box, box = daylight()
    local Chat = stub.chatModule.Chat
    local hold = Chat.Hold
    Chat.Hold = function() error("hold broke") end
    ChatFrame1:SetAlpha(1)
    Chat.Pass()
    Chat.Hold = hold
    T.eq(ChatFrame1:GetAlpha(), 0, "parked again")
    T.truthy(#stub.errors > 0, "the failing step is still reported")
    stub.errors = {}
end)

T.test("chat daylight: a plugin's formatter changes or drops a line; its links come back to it", function()
    local Box, box = daylight()
    local me = DaylightUI.API.For("Chatty")
    local seen
    local h = me.FormatChat(function(text, info)
        seen = info
        if info.body == "spam me" then return false end
        return text .. " (ok)"
    end)
    said(ChatFrame1, "Bob: hi", "CHAT_MSG_GUILD", 21)
    local texts = boxTexts(box)
    T.truthy(string.find(texts[#texts], "(ok)", 1, true), "changed")
    T.eq(seen.event, "CHAT_MSG_GUILD"); T.eq(seen.kind, "guild"); T.eq(seen.sender, "Bob"); T.eq(seen.body, "Bob: hi")
    local n = #boxTexts(box)
    said(ChatFrame1, "spam me", "CHAT_MSG_GUILD", 22)
    T.eq(#boxTexts(box), n, "left out")
    DaylightUI.API.Off(h)
    said(ChatFrame1, "Bob: bye", "CHAT_MSG_GUILD", 23)
    texts = boxTexts(box)
    T.falsy(string.find(texts[#texts], "(ok)", 1, true), "stopped")
    -- A link of the plugin's, clicked in the box.
    local got
    me.OnChatLink(function(data) got = data end)
    local link = me.ChatLink("fish:42", "Show fish")
    T.truthy(string.find(link, "|Hdaylightchat:plugin:Chatty:fish:42|h[Show fish]|h", 1, true))
    stub.chatModule.Extras.OnLink("daylightchat:plugin:Chatty:fish:42")
    T.eq(got, "fish:42")
end)

-- The game's won line names the item and the count, not the price. The total
-- quoted just before the buy goes on it, split by the count.
T.test("chat: a won commodity auction says what each one cost", function()
    _G.ERR_AUCTION_COMMODITY_WON_S = "You won an auction for %s x%d"
    local _, box = daylight()
    local Money = DaylightUI.Widgets.Money
    local function last() return boxTexts(box)[box:GetNumMessages()] end
    stub.FireEvent("COMMODITY_PRICE_UPDATED", 345, 4830)
    ChatFrame1:AddMessage("Bob says hi", 1, 1, 1, 1)
    T.eq(last(), "Bob says hi", "another line while a quote waits")
    ChatFrame1:AddMessage("You won an auction for Linen Cloth x14", 1, 1, 0, 1)
    T.eq(last(), "You won an auction for Linen Cloth x14 (" .. Money(345) .. " each)", "4830 over 14, rounded")
    stub.Advance(1)
    ChatFrame1:AddMessage("You won an auction for Linen Cloth x14", 1, 1, 0, 1)
    T.eq(last(), "You won an auction for Linen Cloth x14", "the quote went with its line")
    stub.FireEvent("COMMODITY_PRICE_UPDATED", 500, 500)
    ChatFrame1:AddMessage("You won an auction for Wool Cloth x1", 1, 1, 0, 1)
    T.eq(last(), "You won an auction for Wool Cloth x1", "one alone: nothing to split")
    stub.Advance(1)
    stub.FireEvent("COMMODITY_PRICE_UPDATED", 10, stub.Secret(900))
    ChatFrame1:AddMessage("You won an auction for Wool Cloth x3", 1, 1, 0, 1)
    T.eq(last(), "You won an auction for Wool Cloth x3", "a secret total is left alone")
    stub.FireEvent("COMMODITY_PRICE_UPDATED", 300, 900)
    stub.FireEvent("AUCTION_HOUSE_CLOSED")
    ChatFrame1:AddMessage("You won an auction for Wool Cloth x3", 1, 1, 0, 1)
    T.eq(last(), "You won an auction for Wool Cloth x3", "the house closed: no price")
    _G.ERR_AUCTION_COMMODITY_WON_S = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chat: Classic windows get the price of each one too", function()
    _G.ERR_AUCTION_COMMODITY_WON_S = "You won an auction for %s x%d"
    login()
    stub.chatModule.Chat.Pass()
    stub.FireEvent("COMMODITY_PRICE_UPDATED", 345, 4830)
    ChatFrame1:AddMessage("You won an auction for Linen Cloth x14", 1, 1, 0, 1)
    ChatFrame1:FakeRefresh()
    local want = "You won an auction for Linen Cloth x14 (" .. DaylightUI.Widgets.Money(345) .. " each)"
    T.eq(ChatFrame1.visibleLines[1]:GetText(), want)
    _G.ERR_AUCTION_COMMODITY_WON_S = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
