-- The chat options page, as data.

local _, ns = ...

local matching = function(get) return get("matchInfo") == true end
-- Classic is also what shows with the game's controller UI on (Box.On).
local classicStyle = function(get) return get("style") == "classic" or DaylightUI.Pad.On() end
local linkTipsOff = function(get) return get("linkTooltips") ~= true end
local sideOff = function() return not ns.Tabs.SideShown() end
local noBackground = function(get) return get("panelShown") ~= true end
local globalLook = function(get) return get("frameStyle.global") ~= false end
-- The border color rows use the same words and choices as the action bars.
local COLOR_MODE = { shell = "Default", accent = "Accent color", class = "Class color", custom = "One color" }
local COLOR_MODE_ORDER = { "shell", "accent", "class", "custom" }
local lookRows = DaylightUI.Options.LookRows("frameStyle", noBackground, nil, {
    { type = "dropdown", key = "borderColor", label = "Chat border color", values = COLOR_MODE, order = COLOR_MODE_ORDER,
      desc = "The color of every chat panel's border. The border still lights up in your accent color while you drag a corner to size the chat." },
    { type = "color", key = "borderCustom", label = "Custom chat border color",
      desc = "The border color when Chat border color is set to One color.",
      disabled = function(get) return get("borderColor") ~= "custom" end },
})

-- Words and phrases the spam filter hides: an input to add one, then a row per
-- word with an X.
local WORD_LINE = 26
local WORD_ADD = 42 -- input row

local function refreshPanel()
    local panel = DaylightUI.OptionsPanel
    if panel and panel.IsShown() then panel.Refresh() end
end

local function wordLine(row)
    local W, Motion = DaylightUI.Widgets, DaylightUI.Motion
    local line = CreateFrame("Frame", nil, row.list)
    line:SetHeight(WORD_LINE)
    line.text = W.Font(line, W.BODY, DaylightUI.Style.SIZE.body, W.COLORS.text)
    line.text:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.text:SetPoint("RIGHT", line, "RIGHT", -(W.LIST_TOOL + 12), 0)
    line.delete = W.DeleteButton(line)
    line.delete:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    line.delete:SetScript("OnClick", function()
        if line.going then return end
        line.going = true
        Motion.Fade(line, 1, 0, Motion.FAST)
        local word = line.word
        C_Timer.After(Motion.FAST, function()
            line.going = nil
            ns.Extras.SpamRemove(word)
            refreshPanel()
        end)
    end)
    return line
end

local spamWordList = {
    type = "custom", label = "Words and phrases to hide",
    build = function(row)
        local W, Style = DaylightUI.Widgets, DaylightUI.Style
        local L = DaylightUI.L
        row.lines = {}
        row.input = W.Input(row, { hint = L["A word or phrase"], maxLetters = 100 })
        row.input:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -8)
        row.input:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(W.PAD + 90), -8)
        row.add = W.Button(row, ADD or L["Add"], W.INPUT_H)
        row.add:SetWidth(80)
        row.add:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, -8)
        local function add()
            local word = strtrim(row.input:GetText() or "")
            if ns.Extras.SpamAdd(word) then row.fresh = word end
            row.input:SetText("")
            refreshPanel()
        end
        row.add:SetScript("OnClick", add)
        row.input:SetScript("OnEnterPressed", add) -- keep focus for the next word
        row.list = CreateFrame("Frame", nil, row)
        row.list:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -WORD_ADD)
        row.list:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, -WORD_ADD)
        row.empty = W.Font(row.list, W.BODY, Style.SIZE.body, Style.INK.LABEL)
        row.empty:SetPoint("LEFT", row.list, "LEFT", 0, 0)
        row.empty:SetText(L["No words yet."])
    end,
    update = function(row)
        local W, Motion = DaylightUI.Widgets, DaylightUI.Motion
        local list = ns.Extras.SpamList()
        for i, word in ipairs(list) do
            local line = row.lines[i]
            if not line then
                line = wordLine(row)
                row.lines[i] = line
            end
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", row.list, "TOPLEFT", 0, -(i - 1) * WORD_LINE)
            line:SetPoint("TOPRIGHT", row.list, "TOPRIGHT", 0, -(i - 1) * WORD_LINE)
            line.word = word
            line.text:SetText(word)
            W.Stripe(line, i % 2 == 0)
            line:Show()
            if word == row.fresh then Motion.Fade(line, 0, 1, Motion.FAST)
            elseif not line.going then line:SetAlpha(1) end
        end
        row.fresh = nil
        for i = #list + 1, #row.lines do row.lines[i]:Hide() end
        row.count = #list
        row.empty:SetShown(#list == 0)
        row.list:SetHeight(math.max(WORD_LINE, #list * WORD_LINE))
    end,
    height = function(row)
        return WORD_ADD + math.max(1, row.count or #ns.Extras.SpamList()) * WORD_LINE + 6
    end,
}

-- Your own short tags: a box per chat kind and channel, showing the default until you type.
local TAG_LINE = 28
local TAG_W = 56
local TAG_TOP = 8
local TAG_NOTE = 30 -- the note under the boxes

local function tagLine(row, side)
    local W, Style = DaylightUI.Widgets, DaylightUI.Style
    local L = DaylightUI.L
    local line = CreateFrame("Frame", nil, row)
    line:SetHeight(TAG_LINE)
    line.text = Style.Text(line, Style.SIZE.body, "LEFT")
    line.text:SetWordWrap(false)
    line.box = W.Input(line, { height = 22, size = Style.SIZE.small, justify = "CENTER",
        maxLetters = ns.Tags.TAG_LETTERS,
        onChange = function(text, user) if user and line.kind then ns.Tags.SetOwn(line.kind, text) end end })
    line.box:SetWidth(TAG_W)
    line.box.hint.english = true -- the standard tag's letters, not a text to translate
    line.box:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    line.text:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.text:SetPoint("RIGHT", line.box, "LEFT", -8, 0)
    line.box:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        DaylightUI.Tips.Clear()
        DaylightUI.Tips.Title(line.words or "")
        DaylightUI.Tips.Text(string.format(L["The short tag before these messages. Left empty it stays [%s]."],
            line.standard or ""))
        DaylightUI.Tips.Flush()
        GameTooltip:Show()
    end)
    line.box:HookScript("OnLeave", function() GameTooltip:Hide() end)
    line.side = side
    return line
end

local function placeTagLine(row, line, i)
    local W = DaylightUI.Widgets
    local y = -(TAG_TOP + (i - 1) * TAG_LINE)
    line:ClearAllPoints()
    if line.side == 1 then
        line:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, y)
        line:SetPoint("TOPRIGHT", row, "TOP", -12, y)
    else
        line:SetPoint("TOPLEFT", row, "TOP", 12, y)
        line:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, y)
    end
end

local function fillTagColumn(row, items, side)
    local pool = row.columns[side]
    for i, item in ipairs(items) do
        local line = pool[i]
        if not line then
            line = tagLine(row, side)
            pool[i] = line
        end
        placeTagLine(row, line, i)
        line.kind, line.words, line.standard = item.kind, item.words, item.standard
        line.text:SetText(item.words)
        local c = ns.Filter.ColorOf(item.kind)
        line.text:SetTextColor(c[1], c[2], c[3], 1)
        line.box.hint:SetText(item.standard or "")
        if not line.box:HasFocus() then line.box:SetText(ns.Tags.Own(item.kind) or "") end
        line:Show()
    end
    for i = #items + 1, #pool do pool[i]:Hide() end
    return #items
end

local shortTagList = {
    type = "custom", label = "Your own short tags",
    hidden = function(get) return get("shortTags") ~= true end,
    build = function(row)
        local W, Style = DaylightUI.Widgets, DaylightUI.Style
        row.columns = { {}, {} }
        row.note = W.Font(row, W.BODY, Style.SIZE.small, Style.INK.LABEL)
        row.note:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", W.PAD, 8)
        row.note:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -W.PAD, 8)
        row.note:SetJustifyH("LEFT")
        row.note:SetText(DaylightUI.L["Leave a field empty to use the default."])
    end,
    update = function(row)
        local chat, channels = ns.Filter.TagItems()
        row.count = math.max(fillTagColumn(row, chat, 1), fillTagColumn(row, channels, 2))
    end,
    height = function(row)
        local chat, channels = ns.Filter.TagItems()
        return TAG_TOP + math.max(#chat, #channels, row.count or 0) * TAG_LINE + TAG_NOTE
    end,
}

-- When the chat gets out of the way is one choice (hides), in the shared Opacity
-- and fade card. It covers what the Fade, Faded opacity, mouseover, target and
-- delay rows do for other areas, so only Opacity shows here (and on General > Fade).
-- The second panel's own choice counts too while it has one.
local HIDES = { never = "Never", fights = "In fights", fightsIdle = "In fights and when idle", always = "Always (floating)" }
local HIDES_ORDER = { "never", "fights", "fightsIdle", "always" }
local SIDE_HIDES = { chat = "As the main chat" }
for k, v in pairs(HIDES) do SIDE_HIDES[k] = v end
local SIDE_HIDES_ORDER = { "chat", "never", "fights", "fightsIdle", "always" }
local function sideHides(get)
    local own = get("sideHides")
    if classicStyle(get) or not ns.Tabs.SideShown() or own == "chat" then return nil end
    return own
end
local function notIdle(get) return get("hides") ~= "fightsIdle" and sideHides(get) ~= "fightsIdle" end
local hidesCard = DaylightUI.Fade.Card("fade.", {
    { type = "dropdown", key = "hides", label = "Chat hides",
      values = HIDES, order = HIDES_ORDER,
      desc = "In fights: the panel and tabs float away and the messages stay over the world. When idle: the whole chat also fades when nothing new has come in for a while. Always: no panel or tabs while you play, only messages. The mouse over the chat or pressing Enter brings it back." },
    { type = "slider", key = "idleAfter", label = "Chat idle time", min = 3, max = 120, step = 1,
      desc = "How many seconds with no new messages before the chat fades.", disabled = notIdle },
    { type = "toggle", key = "ignoreGains", label = "Loot and XP don't wake the chat",
      desc = "Loot, money, XP, reputation and skill-ups don't bring the chat back, so it stays out of the way while you grind. Whispers, party, guild and other messages still do.",
      disabled = notIdle },
    { type = "slider", key = "lineTime", label = "Chat message fade time", min = 3, max = 120, step = 1,
      desc = "While the panel is away, how many seconds each message stays before it fades. A new message doesn't bring old ones back. Move the mouse over the chat to see them all again.",
      disabled = function(get)
          local own = sideHides(get)
          return get("hides") == "never" and (own == nil or own == "never")
      end },
})
for _, item in ipairs(hidesCard.items) do
    if item.key ~= "fade.opacity" and string.find(item.key, "^fade%.") then
        item.hidden = function() return true end
    end
end

-- The Message colors card shows the game's own colors per message kind, read and
-- set through the game (Chat.ColorOf / Chat.SetColor), so there's nothing to reset.
local function color(chatType, label, desc)
    return { type = "color", label = label, desc = desc,
             get = function() return ns.Chat.ColorOf(chatType) end,
             set = function(v) ns.Chat.SetColor(chatType, v) end }
end

ns.MESSAGE_COLORS = {
    color("SAY", "Say color", "Messages people /say near you."),
    color("YELL", "Yell color", "Messages people /yell, heard across a wider area."),
    color("EMOTE", "Emote color", "Emotes like /wave and /e text."),
    color("WHISPER", "Whisper color", "Whispers you get and send."),
    color("BN_WHISPER", "Battle.net whisper color", "Whispers from your Battle.net friends, and yours to them."),
    color("PARTY", "Party color", "Party chat from everyone but the leader."),
    color("PARTY_LEADER", "Party leader color", "Party chat from the group's leader."),
    color("RAID", "Raid color", "Raid chat from everyone but the leader."),
    color("RAID_LEADER", "Raid leader color", "Raid chat from the raid's leader."),
    color("RAID_WARNING", "Raid warning color", "Raid warnings, the big messages leaders and assistants send."),
    color("INSTANCE_CHAT", "Instance color", "Instance chat, used in battlegrounds and groups made by the group finder."),
    color("GUILD", "Guild color", "Guild chat."),
    color("OFFICER", "Officer color", "Your guild's officer chat."),
    color("CHANNEL1", "Channel 1 color", "Usually General."),
    color("CHANNEL2", "Channel 2 color", "Usually Trade."),
    color("CHANNEL3", "Channel 3 color", "Usually Local Defense."),
    color("CHANNEL4", "Channel 4 color", "Usually Looking for Group."),
    color("CHANNEL5", "Channel 5 color", "The fifth chat channel you joined, often a custom one."),
    color("SKILL", "Skill-up color", "\"Your skill in Tailoring has increased\" and the like."),
    color("TRADESKILLS", "Crafting color", "\"You create...\" and other crafting messages."),
    color("LOOT", "Loot color", "\"You receive loot\" lines and other loot messages."),
    color("MONEY", "Money color", "Lines for money you loot."),
    color("COMBAT_XP_GAIN", "Experience color", "Lines for the experience you gain."),
    color("COMBAT_FACTION_CHANGE", "Reputation color", "Lines for reputation you gain or lose."),
    color("SYSTEM", "System message color", "The game's own messages: logins, /played, errors and the like."),
    color("ACHIEVEMENT", "Achievement color", "Achievement announcements."),
}

ns.OPTIONS = { pages = {
    { id = "chat", label = "Chat",
      desc = "Daylight UI's chat box, with whispers as conversations, or the game's own windows (Classic).",
      groups = {
        { label = "Panel", tab = "Panel", desc = "Move it in unlock mode (/dui unlock).", items = {
            { type = "dropdown", key = "style", label = "Chat style",
              values = { daylight = "Daylight", classic = "Classic" }, order = { "daylight", "classic" },
              desc = "Daylight: Daylight UI's own chat box, with its own tabs. Classic: the game's chat windows and tabs in the Daylight look. Switching is instant, and both keep every message. With the game's controller mode on, chat is Classic, since the game's chat windows have its controller buttons." },
            { type = "toggle", key = "matchInfo", label = "Match the info panel's size",
              desc = "The same size as the top-right panel with its damage meter out." },
            { type = "slider", key = "width", label = "Chat width", min = 250, max = 1000, step = 1, unit = "px",
              desc = "You can also drag the chat's bottom-right corner to size it.", disabled = matching },
            { type = "slider", key = "height", label = "Chat height", min = 100, max = 600, step = 1, unit = "px",
              desc = "You can also drag the chat's bottom-right corner to size it.", disabled = matching },
            { type = "toggle", key = "panelShown", label = "Chat background",
              desc = "The panel behind the chat, with its border. When off, only the chat text shows." },
        } },
        { label = "Borders and background", desc = "Every chat panel: the main one, the second one and a chat window pulled out on its own. On the global style the Classic chat keeps a thin line.", items = lookRows },
        { label = "Second panel", desc = "Move it in unlock mode (/dui unlock).", items = {
            { type = "toggle", label = "Second chat panel",
              get = function() return ns.Tabs.SideShown() end,
              set = function(v) ns.Tabs.ShowSide(v) end,
              hidden = classicStyle,
              desc = "A second chat box with its own tabs, for loot, guild or a combat log. Right-click a chat tab to move it over, or drag it onto the other panel. Typing and whispers stay in the main chat." },
            { type = "slider", key = "sideWidth", label = "Second panel width", min = 150, max = 1000, step = 1, unit = "px",
              desc = "You can also drag the panel's bottom-right corner to size it.",
              hidden = classicStyle, disabled = sideOff },
            { type = "slider", key = "sideHeight", label = "Second panel height", min = 100, max = 600, step = 1, unit = "px",
              desc = "You can also drag the panel's bottom-right corner to size it.",
              hidden = classicStyle, disabled = sideOff },
            { type = "toggle", key = "sideAlphaOwn", label = "Separate second panel background opacity",
              desc = "Gives the second chat panel its own background opacity, set in the row below. When off, it's as see-through as the main chat panel. Shown while the chat's Use Daylight UI global style is off.",
              hidden = function(get) return classicStyle(get) or globalLook(get) end,
              disabled = function(get) return sideOff() or noBackground(get) end },
            { type = "slider", key = "sideAlpha", label = "Second panel background opacity", min = 0, max = 1, step = 0.05, unit = "%",
              desc = "How solid the second chat panel's background is: 0 is fully see-through.",
              hidden = function(get) return classicStyle(get) or globalLook(get) or get("sideAlphaOwn") ~= true end,
              disabled = function(get) return sideOff() or noBackground(get) end },
            { type = "toggle", key = "sideTextSizeOwn", label = "Separate second panel text size",
              desc = "Gives the second chat panel its own text size, set in the row below. When off, it matches the main chat's text size.",
              hidden = classicStyle, disabled = sideOff },
            { type = "slider", key = "sideTextSize", label = "Second panel text size", min = 8, max = 24, step = 1, unit = "px",
              desc = "The size of the messages on the second chat panel.",
              hidden = function(get) return classicStyle(get) or get("sideTextSizeOwn") ~= true end,
              disabled = sideOff },
            { type = "dropdown", key = "sideAlign", label = "Second panel message alignment",
              values = { left = "Left", right = "Right" }, order = { "left", "right" },
              desc = "Which edge the second panel's messages line up on, for a loot or combat log panel on the right side of your screen.",
              hidden = classicStyle, disabled = sideOff },
            { type = "dropdown", key = "sideHides", label = "Second panel hides",
              values = SIDE_HIDES, order = SIDE_HIDES_ORDER,
              desc = "When the second panel gets out of the way, on its own: keep a loot or combat log panel up while the main chat floats away, or the other way round. Idle time and how long messages stay are the main chat's.",
              hidden = classicStyle, disabled = sideOff },
        } },
        hidesCard,
        { label = "Daylight look", desc = "The Daylight chat box's own look and motion (Chat style: Daylight).", items = {
            { type = "toggle", key = "topLine", label = "Accent line on top",
              desc = "A thin line in your accent color along the top of the chat.", disabled = classicStyle },
            { type = "toggle", key = "tabDots", label = "Count on tabs with new messages",
              desc = "A small number in your accent color after a tab's name: how many new messages landed in it since you last looked.", disabled = classicStyle },
            { type = "toggle", key = "mentionGlow", label = "Glow behind your name",
              desc = "A soft glow behind a message that says your name or one of your words. Needs Light up your name, or some Words to light up.",
              disabled = function(get) return classicStyle(get) or (get("alertName") ~= true and (get("alertWords") or "") == "") end },
            { type = "toggle", key = "lineFadeIn", label = "New messages ease in",
              desc = "Each new message fades in instead of appearing at once. Never in a fight.", disabled = classicStyle },
            { type = "toggle", key = "typeLift", label = "Messages rise while you type",
              desc = "With the chat input at the bottom: while you type, the messages slide up and the box you type in sits under them, so it never covers a line.",
              disabled = function(get) return classicStyle(get) or get("boxInputAt") ~= "bottom" end },
        } },
        { label = "Buttons", items = {
            { type = "toggle", key = "hideButtons", invert = true, label = "Show the chat side buttons", reload = true,
              desc = "The game's chat menu, channel, voice and social buttons next to chat, for Chat style: Classic. The Daylight chat box has its own menu and voice buttons. When off, they're gone; their slash commands still work." },
            { type = "toggle", key = "copyButton", label = "Chat copy button",
              desc = "A small Copy button at the top-right of the chat. It opens the tab's text so you can select it and press Ctrl+C. /dui copy does the same." },
            { type = "toggle", key = "menuButton", label = "Chat menu button", hidden = classicStyle,
              desc = "A small button at the top-right of the chat for the game's chat menu: pick the language you speak, emotes, say, yell and more." },
            { type = "toggle", key = "voiceButton", label = "Voice chat button", hidden = classicStyle,
              desc = "A small headset button at the top-right of the chat. It opens the game's Chat Channels window, where you join voice chat with your party, raid or a channel." },
        } },
        { label = "Text", tab = "Messages", items = {
            { type = "slider", key = "textSize", label = "Chat text size", min = 8, max = 24, step = 1, unit = "px",
              get = function() return ns.Chat.TextSize() end,
              set = function(v) return DaylightUI:Set("Chat", "textSize", v) end,
              desc = "The size of the messages in every chat window. Each chat tab's right-click menu sets it too." },
            DaylightUI.Options.FontRow("media.font", "Chat font", "The chat window's text and the chat bubbles"),
            { type = "toggle", key = "outline", label = "Chat text outline", desc = "A thin outline on chat text." },
            { type = "slider", key = "lineSpacing", label = "Line spacing", min = 0, max = 12, step = 1, unit = "px",
              hidden = classicStyle,
              desc = "Extra space between the lines of the Daylight chat box, so messages sit further apart. 0 is the game's own spacing." },
            { type = "dropdown", key = "align", label = "Message alignment",
              values = { left = "Left", right = "Right" }, order = { "left", "right" },
              hidden = classicStyle,
              desc = "Which edge the messages line up on. Right suits a chat on the right side of your screen." },
            { type = "slider", key = "tabSize", label = "Chat tab text size", min = 10, max = 18, step = 1, unit = "px",
              desc = "The size of the words on the chat tabs." },
            { type = "toggle", key = "inputSizeOwn", label = "Separate chat input text size",
              desc = "Gives the box you type in its own text size, set in the row below. When off, it matches the messages' text size." },
            { type = "slider", key = "inputSize", label = "Chat input text size", min = 8, max = 24, step = 1, unit = "px",
              desc = "The size of what you type in the chat box.",
              hidden = function(get) return get("inputSizeOwn") ~= true end },
            { type = "dropdown", key = "inputAt", label = "Chat input position",
              values = { top = "At the top (over the tabs)", bottom = "At the bottom", below = "Under the panel" },
              order = { "top", "bottom", "below" },
              hidden = function(get) return not classicStyle(get) end,
              desc = "Where the box you type in appears. Under the panel keeps a strip below the chat for it, so it never covers any text. At the bottom, the Daylight chat box lifts its messages over the box while you type." },
            { type = "dropdown", key = "boxInputAt", label = "Chat input position",
              values = { top = "At the top (over the tabs)", bottom = "At the bottom", below = "Under the panel" },
              order = { "top", "bottom", "below" },
              hidden = classicStyle,
              desc = "Where the box you type in appears. Under the panel keeps a strip below the chat for it, so it never covers any text. At the bottom, the Daylight chat box lifts its messages over the box while you type." },
        } },
        { label = "Messages", items = {
            { type = "toggle", key = "shortTags", label = "Short tags",
              desc = "A short tag before each message instead of the channel's or chat's name, like [G] or [P]. Lines already in chat stay as they were." },
            { type = "toggle", key = "channelNumbers", label = "Keep channel numbers",
              desc = "Numbered channels keep their number in front of the short tag.",
              disabled = function(get) return get("shortTags") ~= true end },
            { type = "dropdown", key = "tagLetters", label = "Tag letters",
              values = { english = "English", native = "Your language" },
              order = { "english", "native" },
              desc = "The short tags start from your language's words (G for Grupo) or from English (P for Party). A tag you type in the list always wins.",
              disabled = function(get) return get("shortTags") ~= true end },
            shortTagList,
            { type = "toggle", key = "worldChannelsFirst", label = "General and Trade first", since = "1.8.0",
              desc = "When another addon joins its own channels before General and Trade, they take /1 and /2. This puts General, Trade and the other world channels back on the first numbers." },
            { type = "toggle", key = "classColors", label = "Class-colored names",
              desc = "Players' names in their class color, in every kind of chat (the game's own setting)." },
            { type = "toggle", key = "levels", label = "Levels beside names",
              desc = "[60] before a player's name, for anyone in your group, guild or friends list, found with /who, or you've targeted or moused over. Someone you haven't seen yet shows no level." },
            { type = "dropdown", key = "timestamps", label = "Timestamps",
              -- The game's six formats (Social settings, TIMESTAMP_FORMAT_*), in its order.
              values = { game = "As the game's setting", none = "None",
                         ["%I:%M "] = "03:27", ["%I:%M:%S "] = "03:27:32",
                         ["%I:%M %p "] = "03:27 PM", ["%I:%M:%S %p "] = "03:27:32 PM",
                         ["%H:%M "] = "15:27", ["%H:%M:%S "] = "15:27:32" },
              order = { "game", "none", "%I:%M ", "%I:%M:%S ", "%I:%M %p ", "%I:%M:%S %p ", "%H:%M ", "%H:%M:%S " },
              desc = "The time before each message (the game's own setting)." },
            { type = "toggle", key = "links", label = "Clickable web links",
              desc = "Web addresses in messages become links; click one to copy it." },
        } },
        { label = "Link tooltips", items = {
            { type = "toggle", key = "linkTooltips", label = "Link tooltips on hover",
              desc = "Hovering an item, spell or quest link in chat shows its tooltip. When off, clicking a link still opens it." },
            { type = "dropdown", key = "linkTooltipSpot", label = "Link tooltip position",
              values = { chat = "Next to the chat", cursor = "At the mouse", game = "In the tooltip spot" },
              order = { "chat", "cursor", "game" },
              disabled = linkTipsOff,
              desc = "Next to the chat sits just above it and never covers the lines. The tooltip spot is the Tooltip handle you move with /dui unlock." },
            { type = "toggle", key = "linkTooltipCompare", label = "Compare with what you wear",
              disabled = linkTipsOff,
              desc = "An item link shows your equipped item beside it, as the game's own compare setting says. When off, it shows only while Shift is held." },
            { type = "slider", key = "linkTooltipDelay", label = "Link tooltip delay", min = 0, max = 1, step = 0.1,
              disabled = linkTipsOff,
              desc = "How many seconds the mouse rests on a link before its tooltip shows, so sweeping across the chat leaves it quiet." },
        } },
        { label = "Filters and alerts", desc = "In the Daylight chat box (Chat style: Daylight).", items = {
            { type = "toggle", key = "spamRepeats", label = "Hide repeated messages",
              desc = "In public channels (General, Trade, say...), the same words from the same person again within a minute are hidden. Guild, group and whispers are never hidden.",
              disabled = classicStyle },
            { type = "toggle", key = "spamAds", label = "Hide gold-seller adverts",
              desc = "Messages in public channels that look like gold or boosting adverts are hidden.",
              disabled = classicStyle },
            { type = "toggle", key = "alertName", label = "Light up your name",
              desc = "When someone writes your name where people talk, it lights up in your accent color and the tab it lands in glows.",
              disabled = classicStyle },
            { type = "button", label = "Words to light up", text = "Edit",
              desc = "More words that light up like your name, separated by commas: a dungeon you want, your guild's name.",
              func = function()
                  DaylightUI.Widgets.Prompt(DaylightUI.L["Words to light up, separated by commas"], DaylightUI:Get("Chat", "alertWords") or "",
                      function(text) DaylightUI:Set("Chat", "alertWords", text) end)
              end,
              disabled = classicStyle },
            { type = "toggle", key = "alertSound", label = "Sound for lit-up words",
              desc = "A soft sound when your name or one of your words shows up.",
              disabled = function(get) return classicStyle(get) or (get("alertName") ~= true and (get("alertWords") or "") == "") end },
            { type = "toggle", key = "groupLines", label = "Group finder helpers",
              desc = "Messages looking for a group get role icons next to tank, healer and dps.",
              disabled = classicStyle },
        } },
        { label = "Words and phrases to hide", desc = "Hides messages with these in public channels, never guild, group or whispers. Whole words; capitals don't matter. Chat style: Daylight only.",
          items = { spamWordList } },
        { label = "Chat history", items = {
            { type = "toggle", key = "arrowHistory", label = "Arrow keys bring back sent messages",
              desc = "In the chat box, Up and Down step through what you sent. Alt+Up and Alt+Down still work as before. While the box is open, the arrow keys don't turn your character." },
            { type = "toggle", key = "history", label = "Keep chat after reload",
              desc = "After /reload, the last messages in each chat tab come back, above a gray line." },
            { type = "toggle", key = "historyLogout", label = "Keep chat after logging out",
              desc = "Your chat also comes back the next time you log in on this character, under a gray line with when you left.",
              disabled = function(get) return get("history") ~= true end },
            { type = "slider", key = "historyLines", label = "Messages kept", min = 20, max = 300, step = 10,
              desc = "How many of the newest messages per chat tab come back after /reload, and after logging out while Keep chat after logging out is on.",
              disabled = function(get) return get("history") ~= true end },
        } },
        { label = "Chat bubbles", items = {
            { type = "toggle", key = "bubbles", label = "Chat bubbles",
              desc = "Daylight UI look for speech bubbles (say, yell, party). Instances keep the game's bubbles, since addons can't change them there." },
            { type = "slider", key = "bubbleSize", label = "Chat bubble text size", min = 6, max = 24, step = 1, unit = "px",
              desc = "Text size in speech bubbles. Applies from the next bubble.",
              disabled = function(get) return get("bubbles") ~= true end },
            { type = "slider", key = "bubbleBand", label = "Accent line", min = 0, max = 8, step = 1, unit = "px",
              desc = "The accent colored line along the bottom of a speech bubble. 0 takes it away.",
              disabled = function(get) return get("bubbles") ~= true end },
            { type = "dropdown", key = "bubbleColor", label = "Accent line color",
              values = { accent = "Accent", class = "Speaker's class" }, order = { "accent", "class" },
              desc = "Speaker's class colors each bubble's line by who is talking. Characters you can't see the class of, and NPCs, keep the accent.",
              disabled = function(get) return get("bubbles") ~= true or get("bubbleBand") == 0 end },
            { type = "slider", key = "bubbleAlpha", label = "Bubble background", min = 0.3, max = 1, step = 0.05, unit = "%",
              desc = "How solid the dark background of a speech bubble is. Lower lets the world show through.",
              disabled = function(get) return get("bubbles") ~= true end },
            { type = "toggle", key = "bubbleCut", label = "Cut corner",
              desc = "The bottom-right corner of a speech bubble is cut off, like Daylight UI's tooltip cards. Off gives four square corners.",
              disabled = function(get) return get("bubbles") ~= true end },
        } },
        { label = "Message colors", desc = "The same colors as in the game's chat settings: a change shows in every chat tab.",
          items = ns.MESSAGE_COLORS },
        { label = "Whispers", tab = "Whispers", items = {
            { type = "dropdown", key = "whisperSound", label = "Whisper sound",
              values = { soft = "Breath", dewdrop = "Dewdrop", hello = "Hello", bell = "Warm bell",
                         pop = "Wood pop", game = "The game's own", none = "None" },
              order = { "soft", "dewdrop", "hello", "bell", "pop", "game", "none" },
              desc = "The sound when someone whispers you. The first five are gentle chimes made for Daylight UI; picking one plays it once." },
            { type = "button", label = "Play whisper sound", text = "Play",
              desc = "Plays the whisper sound picked above.",
              func = function() ns.Whisper.Play() end,
              disabled = function(get) return get("whisperSound") == "none" end },
            { type = "dropdown", key = "guildSound", label = "Guild chat sound", since = "1.8.0",
              values = { soft = "Breath", dewdrop = "Dewdrop", hello = "Hello", bell = "Warm bell",
                         pop = "Wood pop", none = "None" },
              order = { "soft", "dewdrop", "hello", "bell", "pop", "none" },
              desc = "A sound when someone writes in guild or officer chat. Never for your own messages, and at most once every few seconds. Picking one plays it once." },
            { type = "button", label = "Play guild chat sound", since = "1.8.0", text = "Play",
              desc = "Plays the guild chat sound picked above.",
              func = function() ns.Whisper.PlayGuild() end,
              disabled = function(get) return get("guildSound") == "none" end },
            { type = "toggle", key = "whisperTabs", label = "Whispers in their own tab",
              desc = "Each person who whispers you gets a tab next to the others, and the whisper shows in your main tab as well. When off, whispers only show in the main tab.",
              hidden = function(get) return not classicStyle(get) end },
            { type = "dropdown", key = "whispersIn", label = "Whispers show in",
              values = { both = "Their own window and the chat", window = "Their own window", chat = "The chat only" },
              order = { "both", "window", "chat" },
              desc = "Their own window: a tile beside the chat for each person you talk to; click one to open the conversation. The chat only: whispers stay in the chat like any other message.",
              hidden = classicStyle },
            { type = "toggle", key = "whispersButton", label = "Whispers button",
              desc = "A small speech bubble at the top-right of the chat that counts your unread whispers and opens all your conversations. /dui whispers does the same.",
              hidden = classicStyle, disabled = function(get) return get("whispersIn") == "chat" end },
            { type = "toggle", key = "whisperPreview", label = "New whisper preview",
              desc = "A new whisper shows its first words above the tiles for a few seconds. Click it to answer.",
              hidden = classicStyle, disabled = function(get) return get("whispersIn") == "chat" end },
            { type = "dropdown", key = "whisperSide", label = "Whisper side",
              values = { right = "Right of the chat", left = "Left of the chat" }, order = { "right", "left" },
              desc = "The side the whisper tiles and conversations slide out from. Left suits a chat on the right of your screen.",
              hidden = classicStyle, disabled = function(get) return get("whispersIn") == "chat" end },
            { type = "slider", key = "tilesMax", label = "Max whisper tiles", min = 1, max = 12, step = 1,
              desc = "How many people's tiles slide out beside the chat at most.",
              hidden = classicStyle, disabled = function(get) return get("whispersIn") == "chat" end },
            { type = "dropdown", key = "tileArt", label = "Whisper tile picture",
              values = { letter = "Their initial", icon = "Their class icon" }, order = { "letter", "icon" },
              desc = "Their initial in their class's colors, or their class icon from the set picked in Unit Frames (Daylight UI's own or a Jiberish style).",
              hidden = classicStyle, disabled = function(get) return get("whispersIn") == "chat" end },
            { type = "slider", key = "tileSize", label = "Whisper tile size", min = 24, max = 56, step = 1, unit = "px",
              desc = "The size of each whisper tile.",
              hidden = classicStyle, disabled = function(get) return get("whispersIn") == "chat" end },
            { type = "slider", key = "previewTime", label = "Whisper preview time", min = 2, max = 20, step = 1,
              desc = "How many seconds a new whisper's preview stays.",
              hidden = classicStyle,
              disabled = function(get) return get("whispersIn") == "chat" or get("whisperPreview") ~= true end },
            { type = "dropdown", key = "cardAt", label = "Conversation position",
              values = { side = "Beside the chat", above = "Above the chat", free = "Where you dragged it" },
              order = { "side", "above", "free" },
              desc = "Where a whisper conversation opens. Drag one by its top to put it anywhere on your screen, and drag its corner to resize it.",
              hidden = classicStyle, disabled = function(get) return get("whispersIn") == "chat" end },
            { type = "slider", key = "cardWidth", label = "Conversation width", min = 160, max = 600, step = 10, unit = "px",
              desc = "The width of a whisper conversation.",
              hidden = classicStyle, disabled = function(get) return get("whispersIn") == "chat" end },
            { type = "slider", key = "cardHeight", label = "Conversation height", min = 180, max = 700, step = 10, unit = "px",
              desc = "The height of a whisper conversation above the chat or dragged away. Beside the chat it's as tall as the chat.",
              hidden = classicStyle,
              disabled = function(get) return get("whispersIn") == "chat" or get("cardAt") == "side" end },
            { type = "toggle", key = "awayOn", label = "Away message",
              desc = "Answers whispers for you, once per person every 15 minutes. Someone you whispered in that time doesn't get it.", hidden = classicStyle },
            { type = "dropdown", key = "awayWhen", label = "Away message answers",
              values = { away = "When you're away", instance = "In a dungeon or raid", combat = "In a fight" },
              order = { "away", "instance", "combat" },
              desc = "When the away message answers.",
              hidden = classicStyle, disabled = function(get) return get("awayOn") ~= true end },
            { type = "button", label = "Away message text", text = "Edit",
              desc = "What the away message says.",
              func = function()
                  DaylightUI.Widgets.Prompt(DaylightUI.L["Away message"], DaylightUI:Get("Chat", "awayText") or "",
                      function(text) DaylightUI:Set("Chat", "awayText", text) end)
              end,
              hidden = classicStyle, disabled = function(get) return get("awayOn") ~= true end },
        } },
    } },
} }
