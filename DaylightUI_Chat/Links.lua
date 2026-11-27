-- Clickable web addresses in chat. An http(s):// or www. address becomes a link
-- that opens a box with the address selected for copying (the game can't open
-- a browser).
--
-- Done with a message event filter before the game builds the line; the chat
-- frames themselves aren't touched. The filter only returns a new message when
-- there's something to link. Otherwise (disabled, secret message, no address)
-- it returns nothing and the game uses its own. The link uses the game's addon
-- link type, whose clicks reach addons through EventRegistry "SetItemRef".

local _, ns = ...
local DUI = DaylightUI
local secret = DUI.IsSecret
local L = DUI.L
local Style = DUI.Style

local Links = {}
ns.Links = Links

Links.COLOR = "7fb4e6" -- soft blue, reads as a link on the dark panel
Links.PREFIX = "addon:DaylightUI:url:"
Links.BOX_WIDTH = 420

local function isURL(word)
    return string.find(word, "^https?://%S") ~= nil or string.find(word, "^www%.[%w%-]+%.%a") ~= nil
end

-- The message with its addresses linked, or nil if there are none or it can't
-- be read.
function Links.Wrap(msg)
    if type(msg) ~= "string" or secret(msg) then return nil end
    if not (string.find(msg, "://", 1, true) or string.find(msg, "www.", 1, true)) then return nil end
    local changed = false
    local out = string.gsub(msg, "%S+", function(word)
        -- Skip anything inside the game's own links and color codes.
        if string.find(word, "|", 1, true) or not isURL(word) then return nil end
        -- Trailing punctuation stays outside the link.
        local url, tail = string.match(word, "^(.-)([%.,;:!%?%)%]]*)$")
        if url == "" then return nil end
        changed = true
        return "|cff" .. Links.COLOR .. "|H" .. Links.PREFIX .. url .. "|h[" .. url .. "]|h|r" .. tail
    end)
    return changed and out or nil
end

-- ---------------------------------------------------------------------
-- The copy box
-- ---------------------------------------------------------------------

local box
local function buildBox()
    box = CreateFrame("Frame", "DaylightUILinkBox", UIParent)
    DUI.Movers.FollowScale(box)
    box:SetSize(Links.BOX_WIDTH, 62)
    box:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    box:SetFrameStrata("DIALOG")
    Style.Shell(box)
    box.title = Style.Text(box, Style.SIZE.small, "LEFT")
    box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8)
    box.title:SetText(L["Ctrl+C to copy, Escape to close"])
    -- Read-only: typing restores the address, selected.
    local eb
    eb = DUI.Widgets.Input(box, { onChange = function(_, user)
        if user and box.url then
            eb:SetText(box.url)
            eb:HighlightText()
        end
    end })
    eb:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 10, 8)
    eb:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -10, 8)
    local function close(self)
        self:ClearFocus()
        DUI.Motion.Vanish(box)
    end
    eb:SetScript("OnEscapePressed", close)
    eb:SetScript("OnEnterPressed", close)
    box.edit = eb
    box:Hide()
    DUI.Motion.Window(box, 6)
end

function Links.Show(url)
    if not box then buildBox() end
    box.url = url
    box:Show()
    box.edit:SetText(url)
    box.edit:SetFocus()
    box.edit:HighlightText()
end

function Links.OnClick(link)
    if type(link) ~= "string" or secret(link) then return end
    local url = string.match(link, "^" .. string.gsub(Links.PREFIX, "%p", "%%%0") .. "(.+)$")
    if url then Links.Show(url) end
end

-- ---------------------------------------------------------------------
-- Questie's quest links
-- ---------------------------------------------------------------------

-- Questie's chat filter turns quest links into |Hquestie:id:guid|h links that
-- only exist on screen. Shift-clicked, the game pastes them as is, and only the
-- game's own link types are sent as links, so the line arrives as plain words.
-- Questie only handles this for the game's chat frames, so the Daylight box does
-- it here: the game's quest link if the quest is in your log, else the text that
-- Questie users' chat turns into a link.
local function questName(text)
    local name = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    name = string.gsub(name, "|r", "")
    name = string.gsub(name, "|H.-|h", "")
    name = string.gsub(name, "|h", "")
    name = string.match(name, "^%[(.*)%]$") or name
    return (string.gsub(name, "^%[[^%]]*%]%s*", ""))
end

-- True if the click put a link in the open edit box; otherwise the game handles it.
function Links.LinkQuestie(link, text, button)
    if button ~= "LeftButton" or type(link) ~= "string" or type(text) ~= "string" then return false end
    if secret(link) or secret(text) then return false end
    local id = string.match(link, "^questie:(%d+)")
    if not id or not (IsModifiedClick and IsModifiedClick("CHATLINK")) then return false end
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if type(insert) ~= "function" then return false end
    local native = type(GetQuestLink) == "function" and GetQuestLink(tonumber(id))
    if type(native) ~= "string" or native == "" then
        native = "[" .. questName(text) .. " (" .. id .. ")]"
    end
    return insert(native) == true
end

-- True for a community invite click, which must never go to SetItemRef from here.
-- The game creates its ticket listener on that click, and if the click came from
-- this box the listener stays untrusted for the whole session:
-- GetLastTicketResponse is refused, and so is every invite after it, even from
-- the game's own windows. RedeemTicket is refused for addons too, so the game's
-- window has to handle it.
function Links.ClubTicket(link, text, button)
    if type(link) ~= "string" or secret(link) then return false end
    if not string.find(link, "^clubTicket:") then return false end
    if button == "LeftButton" and IsModifiedClick and IsModifiedClick("CHATLINK") then
        local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
        if type(insert) == "function" and type(text) == "string"
            and not secret(text) and insert(text) then return true end
    end
    DUI.Print(L["Community invites only open from the game's own chat: set Chat style to Classic, then click it."])
    return true
end

-- ---------------------------------------------------------------------
-- Links the game only opens from its own click
-- ---------------------------------------------------------------------

-- A linked profession or recipe clicked in the Daylight box reached SetItemRef
-- and the game opened nothing: it trusts only a click that is its own. So every
-- shown line of the box gets an invisible twin laid exactly over it, on a frame
-- made from the game's InlineHyperlinkFrameTemplate. That template's link click
-- is the game's InlineHyperlinkFrame_OnClick, which calls SetItemRef as the
-- game's code. Nothing is written to the field it reads (hasIconHyperlinks).
--
-- The twins copy whole lines and follow every redraw and scroll, so a link is
-- covered end to end wherever the mouse lands, even while new lines keep coming.
-- A copy of just the hovered link, placed at the mouse, covered half of it and
-- went away with every new line, so clicks often missed it.
--
-- Names go through the twin too: a name's right-click menu opened from the box's
-- own click carried Daylight UI's taint, and the game then blocked its Copy
-- Character Name. Channel tags go through it as well: a left click opens the
-- chat box with the game's OpenChat, and run from the box's own click that left
-- the game's last chat box tainted, so replying to a whisper in a battleground
-- errored. The links the box handles itself are left as plain words in the
-- twin: the frame takes no mouse, so a click there falls through to the box.
Links.OWN = { clubTicket = true, questie = true, addon = true }

-- Shift-click on a name asks the game's /who; its answer belongs on the tab you
-- asked from, so the box is told (it can't see the game's own click).
local NAMES = { player = true, playerCommunity = true }
function Links.NameClicked(link)
    if type(link) ~= "string" or secret(link) then return end
    local kind = string.match(link, "^(%a+):")
    if NAMES[kind] and IsModifiedClick and IsModifiedClick("CHATLINK") and ns.Box then ns.Box.Asked() end
end

local mirrors = {} -- box -> its twin frame (false if the template is missing)

local function own(kind)
    return Links.OWN[kind] or (ns.Extras and kind == ns.Extras.LINK) or false
end

-- The line with the box's own links turned into their plain words, and whether
-- a link the game must click is left in it.
function Links.Twin(text)
    local any = false
    local out = string.gsub(text, "|H([^:|]+)([^|]*)|h(.-)|h", function(kind, _, shown)
        if own(kind) then return shown end
        any = true
    end)
    return out, any
end

local function makeMirror(box)
    local f = mirrors[box]
    if f ~= nil then return f or nil end
    local ok
    ok, f = pcall(CreateFrame, "Frame", nil, box, "InlineHyperlinkFrameTemplate")
    if not ok or type(f) ~= "table" then mirrors[box] = false return nil end
    f:EnableMouse(false) -- links still take clicks; the wheel, drags and the rest reach the box
    f:SetAlpha(0)        -- the box's own lines are what shows
    f:SetAllPoints(box)
    f:SetClipsChildren(true) -- the box lays one row past its top, cut off the same way
    f.lines = {}
    f.box = box
    -- Hovering a twin's link is hovering the box's: its tooltip, from the box.
    f:SetScript("OnHyperlinkEnter", function(_, link) ns.LinkTips.OnEnter(box, link) end)
    f:SetScript("OnHyperlinkLeave", function() ns.LinkTips.OnLeave(box) end)
    -- After the game's own click: a hidden message shown (or one of yours
    -- rewritten) changed only the game's windows, so the box copies it.
    f:HookScript("OnHyperlinkClick", function(_, link)
        DUI.SafeCall(Links.Censored, link)
        DUI.SafeCall(Links.NameClicked, link)
    end)
    mirrors[box] = f
    return f
end

-- censoredmessage, censoredmessagerewrite and censoredmessageconfirmsend all
-- carry the line's id first.
function Links.Censored(link)
    if type(link) ~= "string" or secret(link) then return end
    local id = string.match(link, "^censoredmessage%a*:(%d+)")
    if id and ns.Box then ns.Box.Rewritten(tonumber(id)) end
end

function Links.Mirror(box) return mirrors[box] or nil end

-- Lays each shown line's twin over it. Runs on every redraw and scroll of the
-- box; a line whose text didn't change is left as it is.
function Links.Sync(box)
    if type(box) ~= "table" or type(box.visibleLines) ~= "table" then return end
    local f = mirrors[box]
    local used = 0
    for i, line in ipairs(box.visibleLines) do
        local text = line:IsShown() and line:GetText()
        local copy, any, hidden
        if secret(text) then
            -- A line that reads secret (every Battle.net whisper) can't be searched
            -- or edited, but a font string still shows it whole: its name stays a
            -- link the game's own click opens. Without a twin the click reached
            -- only the box, which never opens a name.
            copy, any, hidden = text, true, true
        elseif type(text) == "string" and string.find(text, "|H", 1, true) then
            copy, any = Links.Twin(text)
        end
        if any then
            f = f or makeMirror(box)
            if not f then return end
            local t = f.lines[i]
            if not t then
                t = f:CreateFontString(nil, "OVERLAY")
                f.lines[i] = t
            end
            if t.over ~= line then
                t:ClearAllPoints()
                t:SetAllPoints(line)
                t.over = line
            end
            local font, size, flags = line:GetFont()
            if font and (t.font ~= font or t.size ~= size or t.flags ~= flags) then
                t:SetFont(font, size, flags or "")
                t.font, t.size, t.flags = font, size, flags
                t.src = nil
            end
            -- A secret line can't be compared, so it's set again on every redraw and
            -- never kept for the next comparison.
            if hidden or t.src ~= copy then
                t:SetJustifyH(line:GetJustifyH() or "LEFT")
                if line.GetIndentedWordWrap then t:SetIndentedWordWrap(line:GetIndentedWordWrap() and true or false) end
                if line.GetSpacing then t:SetSpacing(line:GetSpacing() or 0) end
                t:SetText(copy)
                t.src = not hidden and copy or nil
            end
            t:Show()
            used = used + 1
        elseif f and f.lines[i] then
            f.lines[i]:Hide()
        end
    end
    if not f then return end
    -- Only rows that held a link have a twin, so the list has holes and its
    -- length can't be trusted: the game can also lay out fewer rows than before.
    local rows = #box.visibleLines
    for i, t in pairs(f.lines) do
        if i > rows then t:Hide() end
    end
    f:SetShown(used > 0)
end

-- ---------------------------------------------------------------------

-- Chat events the filter watches: what players say, in any channel.
Links.EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL" }

function Links.Filter(_, _, msg, ...)
    local out = Links.enabled and Links.Wrap(msg) or nil
    if out then return false, out, ... end
    return false
end

local clicks, filtering = false, false

function Links.Apply(cfg)
    Links.enabled = cfg.links and true or false
    if not clicks and EventRegistry and EventRegistry.RegisterCallback then
        clicks = true
        EventRegistry:RegisterCallback("SetItemRef", function(_, link) Links.OnClick(link) end, Links)
    end
    if filtering then return end
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if type(add) ~= "function" then return end
    filtering = true
    for _, e in ipairs(Links.EVENTS) do add(e, Links.Filter) end
end
