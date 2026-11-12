-- The window that sets what a Daylight chat box tab shows, like the game's chat
-- settings: one switch per kind in three columns (chat, channels, the rest).
-- Each name is in its message color with a swatch to change it (through the
-- game's ChangeChatColor on the kind's main chat type, like the Message colors
-- card). "Everything" is on top; switching one kind off from there keeps the rest.
-- The channels column lists the channels you're in by their game names
-- (Kinds.Joined), then world channels you're not in, then "Other channels".
-- Each channel and chat kind has a small box for a custom short tag (Tags.lua),
-- showing the standard tag until you type. Emotes have no tag, and with Short
-- tags off there are no boxes.
-- The tab name box beside "Everything" renames as you type; left empty it goes
-- back to the old name.
-- Opened from a tab's right-click "Channels" and for each new tab.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local L = DUI.L
local Win = DUI.Win

local Filter = {}
ns.Filter = Filter

Filter.COL_W = 200
Filter.GAP = 20
Filter.TAG_W = 44
Filter.TAG_H = 20
Filter.NAME_H = 26
Filter.WIDE = Filter.COL_W + Filter.TAG_W + 6 -- column with tag boxes
Filter.ROW = 26
Filter.EDGE = 20
Filter.W = 2 * Filter.EDGE + 2 * Filter.GAP + 2 * Filter.WIDE + Filter.COL_W
Filter.SWATCH = 18
Filter.TOP = 16
Filter.LIST_TOP = Filter.TOP + Filter.ROW + 18

-- Columns of Kinds.ORDER kinds. The channels column grows with the channels you've
-- joined (Filter.Fill).
Filter.COLUMNS = {
    { title = L["Chat"], kinds = { "say", "yell", "emote", "whisper", "bnet", "bnalert", "party", "instance",
                                   "raid", "warning", "icons", "pvp", "guild", "officer" } },
    { title = L["Channels"], kinds = { "general", "trade", ns.Kinds.SERVICES, ns.Kinds.TRADE_LOCAL,
                                       "lfg", "defense", "channel" } },
    { title = L["Other"], kinds = { "loot", "currency", "money", "tradeskill", "opening", "progress",
                                    "reputation", "skill", "achievement", "pet", "misc", "npc", "boss", "system" } },
}

-- The chat type each kind takes its name color from.
Filter.COLOR_OF = {
    say = "SAY", yell = "YELL", emote = "EMOTE", whisper = "WHISPER", bnet = "BN_WHISPER",
    party = "PARTY", instance = "INSTANCE_CHAT", raid = "RAID", warning = "RAID_WARNING", guild = "GUILD",
    officer = "OFFICER", channel = "CHANNEL", loot = "LOOT", money = "MONEY",
    progress = "COMBAT_XP_GAIN", reputation = "COMBAT_FACTION_CHANGE", skill = "SKILL",
    achievement = "ACHIEVEMENT", npc = "MONSTER_SAY", boss = "RAID_BOSS_EMOTE", system = "SYSTEM",
    currency = "CURRENCY", tradeskill = "TRADESKILLS", opening = "OPENING", pet = "PET_INFO",
    misc = "COMBAT_MISC_INFO", icons = "TARGETICONS", bnalert = "BN_INLINE_TOAST_ALERT", pvp = "BG_SYSTEM_NEUTRAL",
}

local f, everything, nameBox
local rows, channelRows, tagHeads = {}, {}, {}
local tabIndex

-- A channel kind's color: the joined channel of that kind (CHANNELn, which the
-- game colors lines by), else the plain channel color.
local function channelType(kind)
    for _, c in ipairs(ns.Kinds.Joined()) do
        if c.kind == kind then return "CHANNEL" .. c.id end
    end
    return "CHANNEL"
end

function Filter.TypeOf(kind) return Filter.COLOR_OF[kind] or channelType(kind) end

function Filter.ColorOf(kind) return ns.Chat.ColorOf(Filter.TypeOf(kind)) end

function Filter.SetColor(kind, c)
    ns.Chat.SetColor(Filter.TypeOf(kind), c)
    Filter.Paint()
end

function Filter.Frame() return f end
function Filter.Tab() return tabIndex end
function Filter.Rows() return rows end

local function tab() return tabIndex and ns.Box.Tabs()[tabIndex] end

local function columnX(c) return Filter.EDGE + (c - 1) * (Filter.WIDE + Filter.GAP) end

local function shows(kind)
    local t = tab()
    if not t then return false end
    if kind == "all" then return t.all == true end
    return ns.Kinds.Shows(t, kind)
end

-- A switch row: switch on the left, name beside it. Clicking anywhere on the row
-- toggles it.
local function makeRow(parent, kind, words, tagged)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(tagged and Filter.WIDE or Filter.COL_W, Filter.ROW)
    b.hi = b:CreateTexture(nil, "BACKGROUND")
    b.hi:SetTexture(Win.Parts.WHITE)
    local hi = Win.Parts.HI
    b.hi:SetVertexColor(hi[1], hi[2], hi[3], hi[4])
    b.hi:SetPoint("TOPLEFT", b, "TOPLEFT", -6, 0)
    b.hi:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 6, 0)
    b.hi:Hide()
    b.switch = DUI.Widgets.Switch(b)
    b.switch:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.text = Style.Text(b, Style.SIZE.body, "LEFT")
    b.text:SetPoint("LEFT", b.switch, "RIGHT", 8, 0)
    if kind ~= "all" then
        b.swatch = DUI.Widgets.Swatch(b, b, function() return Filter.ColorOf(b.kind) end,
            function(c) Filter.SetColor(b.kind, c) end)
        b.swatch:SetSize(Filter.SWATCH, Filter.SWATCH)
        b.swatch:SetPoint("RIGHT", b, "RIGHT", 0, 0)
        b.swatch:HookScript("OnEnter", function(self)
            Win.Parts.Light(b.hi, true)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            DUI.Tips.Title(b.words)
            DUI.Tips.Hint(L["Click: pick its color"])
            DUI.Tips.Flush()
        end)
        b.swatch:HookScript("OnLeave", function()
            Win.Parts.Light(b.hi, false)
            GameTooltip:Hide()
        end)
        if tagged then
            b.tag = DUI.Widgets.Input(b, { height = Filter.TAG_H, size = Style.SIZE.small, justify = "CENTER",
                maxLetters = ns.Tags.TAG_LETTERS,
                onChange = function(text, user) if user then ns.Tags.SetOwn(b.kind, text) end end })
            b.tag:SetWidth(Filter.TAG_W)
            b.tag:SetPoint("RIGHT", b.swatch, "LEFT", -6, 0)
            b.tag:HookScript("OnEnter", function(self)
                Win.Parts.Light(b.hi, true)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                DUI.Tips.Title(b.words)
                DUI.Tips.Text(string.format(L["The short tag before these messages. Left empty it stays [%s]."],
                    b.standard or ""))
                DUI.Tips.Flush()
            end)
            b.tag:HookScript("OnLeave", function()
                Win.Parts.Light(b.hi, false)
                GameTooltip:Hide()
            end)
        end
        b.text:SetPoint("RIGHT", b.tag or b.swatch, "LEFT", -6, 0)
    else
        b.text:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    end
    b.text:SetWordWrap(false)
    b.text:SetText(words)
    b.kind, b.words = kind, words
    local function flip() Filter.Flip(b.kind) end
    b:SetScript("OnClick", flip)
    b.switch:SetScript("OnClick", flip)
    b:SetScript("OnEnter", function() Win.Parts.Light(b.hi, true) end)
    b:SetScript("OnLeave", function() Win.Parts.Light(b.hi, false) end)
    b.switch:HookScript("OnEnter", function() Win.Parts.Light(b.hi, true) end)
    b.switch:HookScript("OnLeave", function() Win.Parts.Light(b.hi, false) end)
    return b
end

-- Name in its message color ("Everything" stays white). Kinds the tab hides are
-- dimmed a little so the enabled ones stand out.
local function paint(b)
    local on = shows(b.kind)
    b.switch.SetOn(on)
    if b.swatch then b.swatch.Refresh() end
    if b.kind == "all" then
        Style.InkText(b.text, "VALUE")
    else
        local c = Filter.ColorOf(b.kind)
        b.text:SetTextColor(c[1], c[2], c[3], 1)
    end
    if b.tag then
        DUI.Motion.AlphaTo(b.tag, (b.standard and ns.Tags.enabled) and 1 or 0,
            Win.IsOpen(f) and DUI.Motion.FAST or 0, true)
    end
    local M = DUI.Motion
    local goal = (on or b.kind == "all") and 1 or 0.55
    if M and M.On() and b.text:IsVisible() then
        M.Tween(b.text, b.text:GetAlpha(), goal, M.FAST, function(a) b.text:SetAlpha(a) end)
    else
        b.text:SetAlpha(goal)
    end
end

function Filter.Paint()
    if not f then return end
    local t = tab()
    if t then
        Win.SetTitle(f, string.format(L["Show in %s"], t.name or ""))
        if not nameBox:HasFocus() then nameBox:SetText(t.name or "") end
    end
    for _, head in ipairs(tagHeads) do
        DUI.Motion.AlphaTo(head, ns.Tags.enabled and 1 or 0, Win.IsOpen(f) and DUI.Motion.FAST or 0, true)
    end
    paint(everything)
    for _, b in ipairs(rows) do paint(b) end
end

function Filter.Flip(kind)
    if not tab() then return end
    ns.Tabs.SetKind(tabIndex, kind, not shows(kind))
    Filter.Paint()
end

local function heading(parent, words)
    local h = Style.Text(parent, Win.Parts.HEAD, "LEFT")
    h:SetText(string.upper(words))
    Style.InkText(h, "pop")
    return h
end

-- Channels column rows, top to bottom: { kind, words, standard }. standard is the
-- default tag; "Other channels" has none.
function Filter.ChannelList()
    local out, seen = {}, {}
    for _, c in ipairs(ns.Kinds.Joined()) do
        out[#out + 1] = { kind = c.kind, words = c.name, standard = ns.Tags.Standard(c.name, c.id) }
        seen[c.kind] = true
    end
    for _, kind in ipairs(Filter.COLUMNS[2].kinds) do
        if not seen[kind] then
            out[#out + 1] = { kind = kind, words = ns.Tabs.KIND_WORDS[kind] or kind, standard = ns.Tags.KIND_TAGS[kind] }
        end
    end
    return out
end

local function heightFor(most)
    return Win.HEADER + Filter.LIST_TOP + 22 + most * Filter.ROW + 70
end

-- Rebuilds the channels column; the window resizes to fit.
function Filter.Fill()
    local list = Filter.ChannelList()
    local x = columnX(2)
    local M = DUI.Motion
    local open = Win.IsOpen(f)
    for r, item in ipairs(list) do
        local b = channelRows[r]
        if not b then
            b = makeRow(f.host, item.kind, item.words, true)
            b:SetPoint("TOPLEFT", f.host, "TOPLEFT", x, -(Filter.LIST_TOP + 22 + (r - 1) * Filter.ROW))
            b:Hide()
            channelRows[r] = b
            rows[#rows + 1] = b
        end
        b.kind, b.words, b.standard = item.kind, item.words, item.standard
        b.text:SetText(item.words)
        if not b:IsShown() or b.leaving then
            b.leaving = nil
            b:Show()
            M.Tween(b, open and b:GetAlpha() or 1, 1, M.FAST, function(a) b:SetAlpha(a) end)
        end
    end
    for r = #list + 1, #channelRows do
        local b = channelRows[r]
        if b:IsShown() and not b.leaving then
            b.leaving = true
            M.Tween(b, b:GetAlpha(), open and 0 or 1, open and M.FAST or 0, function(a) b:SetAlpha(a) end,
                function()
                    if b.leaving then
                        b.leaving = nil
                        b:Hide()
                        b:SetAlpha(0)
                    end
                end)
        end
    end
    for _, b in ipairs(rows) do
        if b.tag then
            b.tag.hint:SetText(b.standard or "")
            if not b.tag:HasFocus() then b.tag:SetText(ns.Tags.Own(b.kind) or "") end
        end
    end
    local most = #list
    for _, c in ipairs({ 1, 3 }) do most = math.max(most, #Filter.COLUMNS[c].kinds) end
    local h = heightFor(most)
    if open then
        M.Tween(f, f:GetHeight(), h, M.NORMAL, function(v) f:SetHeight(v) end)
    else
        f:SetHeight(h)
    end
end

-- Joined or left a channel while the window is open.
local function channelsChanged()
    if f and Win.IsOpen(f) then
        Filter.Fill()
        Filter.Paint()
    end
end

local function build()
    f = Win.New({ name = "DaylightUIChatFilter", w = Filter.W, h = heightFor(0), strata = "HIGH" }) -- above any bars it might overlap
    f.onClose = function() Filter.Close() end
    local host = f.host
    everything = makeRow(host, "all", L["Everything"])
    everything:SetPoint("TOPLEFT", host, "TOPLEFT", Filter.EDGE, -Filter.TOP)
    local nameY = -(Filter.TOP + Filter.ROW / 2)
    local nameHead = Style.Text(host, Style.SIZE.small, "LEFT")
    nameHead:SetText(L["Tab name"])
    Style.InkText(nameHead, "LABEL")
    nameHead:SetPoint("LEFT", host, "TOPLEFT", columnX(2), nameY)
    nameBox = DUI.Widgets.Input(host, { height = Filter.NAME_H,
        onChange = function(text, user) if user and tabIndex then ns.Tabs.Rename(tabIndex, strtrim(text)) end end })
    nameBox:SetPoint("LEFT", nameHead, "RIGHT", 10, 0)
    nameBox:SetPoint("RIGHT", host, "TOPLEFT", columnX(2) + Filter.WIDE, nameY)
    nameBox:HookScript("OnEditFocusLost", function() Filter.Paint() end)
    f.nameBox = nameBox
    for c, col in ipairs(Filter.COLUMNS) do
        local x = columnX(c)
        local head = heading(host, col.title)
        head:SetPoint("TOPLEFT", host, "TOPLEFT", x, -Filter.LIST_TOP)
        f["head" .. c] = head
        local line = Win.Parts.Rule(host)
        line:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
        line:SetWidth(c == 3 and Filter.COL_W or Filter.WIDE)
        if c < 3 then
            local tagHead = Style.Text(host, Style.SIZE.small, "RIGHT")
            tagHead:SetText(L["Short tag"])
            Style.InkText(tagHead, "LABEL")
            tagHead:SetPoint("RIGHT", host, "TOPLEFT", x + Filter.WIDE, -(Filter.LIST_TOP + 7))
            tagHeads[c] = tagHead
        end
        if c ~= 2 then
            for r, kind in ipairs(col.kinds) do
                local b = makeRow(host, kind, ns.Tabs.KIND_WORDS[kind] or kind, c == 1)
                b.standard = ns.Tags.CHAT_TAGS[kind]
                b:SetPoint("TOPLEFT", host, "TOPLEFT", x, -(Filter.LIST_TOP + 22 + (r - 1) * Filter.ROW))
                rows[#rows + 1] = b
            end
        end
    end
    f.foot = Win.Parts.Footer(host)
    f.foot:Set({ { text = _G.DONE or L["Done"], primary = true, onClick = function() Filter.Close() end } })
    Win.Drag(f, {})
    Win.Keys(f, function(key)
        if key == "ESCAPE" then Filter.Close(); return true end
    end)
    DUI.RegisterEvent("CHANNEL_UI_UPDATE", channelsChanged)
    DUI.RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", channelsChanged)
end

-- Opens for tab i, or just repaints for another tab.
function Filter.Open(i)
    if not ns.Box.Tabs()[i] then return end
    if not f then build() end
    nameBox:ClearFocus()
    tabIndex = i
    Filter.Fill()
    Filter.Paint()
    if not Win.IsOpen(f) then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        f:SetScale(Win.Scale(1))
        Win.Open(f)
        Win.KeysOn(f, true)
    end
end

function Filter.Close()
    if not (f and Win.IsOpen(f)) then return end
    nameBox:ClearFocus()
    for _, b in ipairs(rows) do
        if b.tag then b.tag:ClearFocus() end
    end
    Win.KeysOn(f, false)
    Win.Close(f)
end

-- Tabs were reordered (from: new index -> old). Follow this tab.
function Filter.Reindex(from)
    local now
    for n = 1, #from do
        if from[n] == tabIndex then now = n end
    end
    tabIndex = now
end

-- Tabs changed (moved, removed). Close if this tab is gone.
function Filter.Changed()
    if not (f and Win.IsOpen(f)) then return end
    if tab() then Filter.Paint() else Filter.Close() end
end

function Filter.Repaint()
    if f then Win.Repaint(f); Filter.Paint() end
end
