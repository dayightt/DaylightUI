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
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return nil end
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
    if type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then return end
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
    if issecretvalue and (issecretvalue(link) or issecretvalue(text)) then return false end
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
    if type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then return false end
    if not string.find(link, "^clubTicket:") then return false end
    if button == "LeftButton" and IsModifiedClick and IsModifiedClick("CHATLINK") then
        local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
        if type(insert) == "function" and type(text) == "string"
            and not (issecretvalue and issecretvalue(text)) and insert(text) then return true end
    end
    DUI.Print(L["Community invites only open from the game's own chat: set Chat style to Classic, then click it."])
    return true
end

-- ---------------------------------------------------------------------
-- Links the game only opens from its own click
-- ---------------------------------------------------------------------

-- A linked profession or recipe clicked in the Daylight box reached SetItemRef
-- and the game opened nothing: it trusts only a click that is its own. So while
-- a link is hovered, an invisible copy of it waits under the mouse on a frame
-- made from the game's InlineHyperlinkFrameTemplate, and the click lands there.
-- That template's link click is the game's InlineHyperlinkFrame_OnClick, which
-- calls SetItemRef as the game's code. Nothing is written to the field it reads
-- (hasIconHyperlinks). The copy also keeps still while the box redraws its lines,
-- which the box does on every left press because its text can be selected.
-- Names, channels and the links the box handles itself stay the box's click:
-- the game's handlers for those want a chat window.
Links.OWN = { player = true, BNplayer = true, playerCommunity = true, BNplayerCommunity = true,
    channel = true, clubTicket = true, questie = true, addon = true }

local catcher, holding -- the copy's frame (false if the template is missing), the box it serves

local function makeCatcher()
    if catcher ~= nil then return catcher or nil end
    local ok, f = pcall(CreateFrame, "Frame", nil, UIParent, "InlineHyperlinkFrameTemplate")
    if not ok or type(f) ~= "table" then catcher = false return nil end
    f:EnableMouse(false) -- links still take clicks; the wheel and drags reach the box
    f:SetAlpha(0)        -- the box's own line is what shows
    f:Hide()
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("CENTER")
    f.text:SetWordWrap(false)
    -- The box already shows the tooltip (LinkTips); the template would show a second.
    f:SetScript("OnHyperlinkEnter", function() end)
    f:SetScript("OnHyperlinkLeave", function() Links.Drop(true) end)
    -- After the game's own click: a hidden message shown (or one of yours
    -- rewritten) changed only the game's windows, so the box copies it.
    f:HookScript("OnHyperlinkClick", function(_, link) DUI.SafeCall(Links.Censored, link) end)
    -- Hidden with the box: let go for good, or it would come back with the box
    -- somewhere the mouse no longer is.
    f:SetScript("OnHide", function(self)
        holding = nil
        self:Hide()
    end)
    catcher = f
    return f
end

-- censoredmessage, censoredmessagerewrite and censoredmessageconfirmsend all
-- carry the line's id first.
function Links.Censored(link)
    if type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then return end
    local id = string.match(link, "^censoredmessage%a*:(%d+)")
    if id and ns.Box then ns.Box.Rewritten(tonumber(id)) end
end

function Links.Catcher() return catcher or nil end
function Links.Holding(box) return holding ~= nil and holding == box end

-- From the box's OnHyperlinkEnter: put the copy of this link under the mouse.
function Links.Hold(box, link, text)
    if type(link) ~= "string" or type(text) ~= "string" then return false end
    if issecretvalue and (issecretvalue(link) or issecretvalue(text)) then return false end
    local kind = string.match(link, "^([^:]+):")
    if not kind or Links.OWN[kind] or (ns.Extras and kind == ns.Extras.LINK) then return false end
    local f = makeCatcher()
    if not f then return false end
    if f:GetParent() ~= box then f:SetParent(box) end
    f:SetFrameStrata(box:GetFrameStrata())
    f:SetFrameLevel(box:GetFrameLevel() + 10)
    -- The box's own font, so the copy is as wide as the line's link.
    local font, size, flags = box:GetFont()
    if font then f.text:SetFont(font, size, flags or "") end
    f.text:SetText(text)
    local h = math.max(f.text:GetStringHeight() or 0, size or 0)
    f:SetSize(math.max(f.text:GetStringWidth() or 0, 1) + 2, h + 2)
    local x, y = GetCursorPosition()
    local scale = f:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (x or 0) / scale, (y or 0) / scale)
    holding = box
    f:Show()
    return true
end

-- Lets the copy go. left: the mouse left it, so the tooltip goes as well.
function Links.Drop(left)
    local box = holding
    holding = nil
    if catcher then catcher:Hide() end
    if box and left then ns.LinkTips.OnLeave(box) end
end

-- The box redrew its lines (new ones came in) or scrolled: the link has moved
-- from under the mouse. A press in progress already landed on it, so it stays.
function Links.Moved(box, scrolled)
    if holding ~= box then return end
    if not scrolled and type(IsMouseButtonDown) == "function" and IsMouseButtonDown() then return end
    Links.Drop(true)
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
