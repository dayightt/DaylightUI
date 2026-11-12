-- Whispers as conversations for the Daylight chat box: one per person, newest
-- activity first, pinned ones on top. Whispers in and out (character and
-- Battle.net) come from a separate event frame. Shown by Tiles.lua (the column
-- beside the chat and the preview), Thread.lua (one conversation), Convo.lua
-- (the card) and Hub.lua (all of them).
--
-- * Saved per character (DB.Character().whispers), newest MAX lines each.
--   Battle.net ones last only for the session: their names are protected
--   strings that can't be saved.
-- * A whisper with secret text or sender (chat lockdown) isn't kept. It still
--   shows in the chat box (Talk.Keeps), as do away, busy and offline notices.
-- * Sending uses C_ChatInfo.SendChatMessage / BNSendWhisper, never during chat
--   lockdown (says so once).
-- * Away message: once per person per AWAY_GAP seconds, while flagged Away, in
--   an instance, or in combat, depending on the setting. Never to someone you
--   whispered in that time. Daylight style only.
-- * Classic style still records whispers for the hub but doesn't count unread.
-- * Notes: one short note per player, account-wide (DB.Root().whisperNotes).

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Talk = {}
ns.Talk = Talk

Talk.MAX = 80          -- lines kept per conversation
Talk.KEEP = 30 -- conversations kept (oldest unpinned go first)
Talk.AWAY_GAP = 900 -- seconds between away replies to the same person

local cfg
local convos = {}      -- key -> conversation
local seq = 0
local awaySent = {}    -- key -> time

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function plain(v) return type(v) ~= "nil" and not secret(v) end

function Talk.Apply(c) cfg = c end
function Talk.On() return cfg ~= nil and ns.Box.On() and cfg.whispersIn ~= "chat" end

-- ---------------------------------------------------------------------
-- The store
-- ---------------------------------------------------------------------

local function saved()
    local char = DUI.DB.Character()
    if type(char.whispers) ~= "table" then char.whispers = {} end
    return char.whispers
end

function Talk.Notes()
    local root = DUI.DB.Root()
    if type(root.whisperNotes) ~= "table" then root.whisperNotes = {} end
    return root.whisperNotes
end

function Talk.Note(c) return c and not c.bn and Talk.Notes()[c.name] or nil end
function Talk.SetNote(c, text)
    if not c or c.bn then return end
    Talk.Notes()[c.name] = (type(text) == "string" and text ~= "") and text or nil
    DUI.Fire("ChatTalk", c.key)
end

function Talk.Get(key) return convos[key] end

-- Pinned first, then by newest activity.
function Talk.List()
    local out = {}
    for _, c in pairs(convos) do if #c.msgs > 0 then out[#out + 1] = c end end
    table.sort(out, function(a, b)
        if (a.pinned == true) ~= (b.pinned == true) then return a.pinned == true end
        return (a.at or 0) > (b.at or 0)
    end)
    return out
end

function Talk.Unread()
    local n = 0
    for _, c in pairs(convos) do n = n + (c.unread or 0) end
    return n
end

-- A player's class from their GUID (when plain), stored on the conversation.
local function learn(c, guid)
    if not plain(guid) or type(guid) ~= "string" or guid == "" then return end
    c.guid = guid
    if type(GetPlayerInfoByGUID) ~= "function" then return end
    local _, class, _, _, _, _, _, level = GetPlayerInfoByGUID(guid)
    if plain(class) and type(class) == "string" then c.class = class end
    if plain(level) and type(level) == "number" and level > 0 then c.level = level end
end

local function make(key, name, bn)
    local c = convos[key]
    if c then return c end
    -- Only saved once something is said (Talk.Add); just opening one doesn't count.
    c = { key = key, name = name, bn = bn, msgs = {}, unread = 0 }
    convos[key] = c
    return c
end

-- Trim to the cap, dropping the oldest unpinned first.
local function trim()
    local list = Talk.List()
    for i = #list, Talk.KEEP + 1, -1 do
        local c = list[i]
        if not c.pinned then convos[c.key] = nil; saved()[c.key] = nil end
    end
end

-- Adds a line to a conversation (me = sent by you).
function Talk.Add(c, text, me)
    seq = seq + 1
    c.at = seq
    c.closed = nil
    table.insert(c.msgs, { t = time(), me = me or nil, text = text })
    if not c.bn then saved()[c.key] = c end
    while #c.msgs > Talk.MAX do table.remove(c.msgs, 1) end
    if not me and ns.Box.On() and not ns.Convo.Showing(c.key) and not ns.Hub.Showing(c.key) then c.unread = (c.unread or 0) + 1 end
    trim()
    DUI.Fire("ChatTalk", c.key, me and "sent" or "heard")
end

function Talk.Read(c)
    if c and (c.unread or 0) > 0 then
        c.unread = 0
        DUI.Fire("ChatTalk", c.key)
    end
end

function Talk.Pin(c, on) c.pinned = on or nil; DUI.Fire("ChatTalk", c.key) end
function Talk.Close(c) c.closed = true; DUI.Fire("ChatTalk", c.key) end
function Talk.Forget(c)
    convos[c.key] = nil
    saved()[c.key] = nil
    DUI.Fire("ChatTalk", c.key)
end

-- Every conversation except pinned ones.
function Talk.ForgetAll()
    for key, c in pairs(convos) do
        if not c.pinned then convos[key] = nil; saved()[key] = nil end
    end
    DUI.Fire("ChatTalk")
end

-- Anything to clear? Pinned ones stay.
function Talk.AnyLoose()
    for _, c in pairs(convos) do
        if not c.pinned and #c.msgs > 0 then return true end
    end
    return false
end

-- Restores saved conversations at login, ordered by last activity.
function Talk.Load()
    local list = {}
    for key, c in pairs(saved()) do
        -- Skip empty ones (opened, nothing said).
        if type(c) == "table" and type(c.msgs) == "table" and #c.msgs > 0 and type(c.name) == "string" then
            c.key = key
            convos[key] = c
            list[#list + 1] = c
        else
            saved()[key] = nil
        end
    end
    table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
    for _, c in ipairs(list) do seq = seq + 1; c.at = seq end
end

-- ---------------------------------------------------------------------
-- Heard
-- ---------------------------------------------------------------------

local function nameKey(name) return "w:" .. name end

Talk.EVENTS = { CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true,
                CHAT_MSG_BN_WHISPER = true, CHAT_MSG_BN_WHISPER_INFORM = true }

-- Would heard() keep this line as part of a conversation? Takes Box.Feed's
-- AddMessage arguments (event and args). Secret parts and away/offline notices: no.
function Talk.Keeps(event, args)
    if secret(event) or not Talk.EVENTS[event] or type(args) ~= "table" then return false end
    local text, sender = args[1], args[2]
    if not plain(text) or type(text) ~= "string" then return false end
    if event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM" then
        local id = args[13]
        return plain(id) and type(id) == "number"
    end
    return plain(sender) and type(sender) == "string" and sender ~= ""
end

local function heard(event, text, sender, ...)
    if not cfg or not plain(text) or type(text) ~= "string" then return end
    local me = event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM"
    local c
    if event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM" then
        local id = select(11, ...)   -- arg13: the Battle.net account id
        if not plain(id) or type(id) ~= "number" then return end
        c = make("bn:" .. id, sender, id)
        if plain(sender) then c.name = sender end
    else
        if not plain(sender) or type(sender) ~= "string" or sender == "" then return end
        c = make(nameKey(sender), sender)
        learn(c, select(10, ...))    -- arg12: the sender's GUID
    end
    Talk.Add(c, text, me)
    -- Whatever sent it (the card, the game's box), you're clearly not away.
    if me then awaySent[c.key] = GetTime() else Talk.Away(c) end
end

function Talk.Listen()
    if Talk.listening then return end
    Talk.listening = true
    for _, e in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
                         "CHAT_MSG_BN_WHISPER_INFORM" }) do
        DUI.RegisterEvent(e, function(event, ...) DUI.SafeCall(heard, event, ...) end)
    end
end

-- ---------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------

function Talk.Locked()
    return C_ChatInfo ~= nil and type(C_ChatInfo.InChatMessagingLockdown) == "function"
        and C_ChatInfo.InChatMessagingLockdown() == true
end

-- True if it was sent. The game reports it back as sent, which heard() picks up.
function Talk.Send(c, text)
    if not c or type(text) ~= "string" then return false end
    text = string.match(text, "^%s*(.-)%s*$")
    if text == "" then return false end
    if Talk.Locked() then
        if not Talk.toldLocked then
            Talk.toldLocked = true
            DUI.Print(L["Chat is locked during this fight: whispers can be sent again after it."])
        end
        return false
    end
    if c.bn then
        if type(BNSendWhisper) ~= "function" then return false end
        BNSendWhisper(c.bn, text)
    else
        C_ChatInfo.SendChatMessage(text, "WHISPER", nil, c.name)
    end
    return true
end

-- ---------------------------------------------------------------------
-- Away
-- ---------------------------------------------------------------------

local function awayNow()
    local when = cfg.awayWhen
    if when == "instance" then return IsInInstance() == true end
    if when == "combat" then return InCombatLockdown() == true end
    -- Like the game's own: only while flagged Away. That flag is secret during chat
    -- lockdown, when nothing can be sent anyway.
    local afk = UnitIsAFK("player")
    if issecretvalue and issecretvalue(afk) then return false end
    return afk == true
end

function Talk.Away(c)
    -- Daylight chat box only (the options are hidden in Classic).
    if not cfg or not cfg.awayOn or not ns.Box.On() or not awayNow() then return end
    local now = GetTime()
    if awaySent[c.key] and now - awaySent[c.key] < Talk.AWAY_GAP then return end
    awaySent[c.key] = now
    local text = cfg.awayText
    if type(text) ~= "string" or text == "" then text = L["I'm away right now, I'll get back to you soon."] end
    Talk.Send(c, text)
end
