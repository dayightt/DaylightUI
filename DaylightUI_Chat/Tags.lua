-- Short channel tags in chat: "[1. General - Tirisfal Glades]" becomes [G], trade
-- [T], guild [G], party [P], raid [R]. "Name says:" becomes "[S] Name:", yells
-- [Y], whispers [W], sent whispers [To]. The game's timestamp is tinted tan so it
-- stays quiet next to the message.
--
-- The game builds each line in its secure chat code, adding "[Guild]" and "says:"
-- after message filters run, and that code reads its format strings, so those are
-- never changed. Instead lines are shortened as the window draws them: the
-- ScrollingMessageFrame "display refreshed" callback (SecureMixin, meant for
-- addons; Feel.lua's line fade uses it too) runs right after the game sets each
-- line's text, in the same frame, so the long text never shows. Each new history
-- entry is shortened once and its visible line updated.
-- Never hook the window's AddMessage: in this client the game's own call to it
-- then fails with "attempt to call a nil value" (ChatFrameOverrides.lua). No
-- TransformMessages either (it breaks item links), and no fields on the window.
-- Secret lines, and every line received during chat lockdown, are left alone.
--
-- Every window but the combat log registers the callback once, from Chat.Pass.

local _, ns = ...

local Tags = {}
ns.Tags = Tags

-- Numbered channels shown by name (spaces removed); others by number.
-- With channelNumbers on (Tags.numbers) named ones keep their number too: [1. G].
Tags.CHANNELS = { General = "G", Trade = "T", LocalDefense = "LD", LookingForGroup = "LFG",
                  WorldDefense = "WD", GuildRecruitment = "GR", NewcomerChat = "N",
                  Services = "TS", ["Trade(Services)"] = "TS", ["Trade(Local)"] = "TL", TradeLocal = "TL",
                  -- Spanish clients name the channels in Spanish.
                  Comercio = "T", Defensalocal = "LD", Buscargrupo = "LFG", Defensamundial = "WD",
                  Defensaglobal = "WD", Reclutamiento = "GR", Novatos = "N", Servicios = "TS",
                  ["Comercio(Servicios)"] = "TS", ["Comercio(Local)"] = "TL" }
-- Custom tags per channel or chat kind come from the channelTags setting (keyed by
-- kind, written whole, set in a tab's Show window, Filter.lua). A custom tag wins;
-- an empty box falls back to the standard one. Standard tags are also the edit
-- box hint when you're not in that channel. Group leaders get an L added (PL),
-- sent whispers stay [To], emotes have no tag.
Tags.own = {}
Tags.KIND_TAGS = { general = "G", trade = "T", lfg = "LFG", defense = "LD",
                   ["ch:trade (services)"] = "TS", ["ch:trade (local)"] = "TL" } -- Kinds.SERVICES, TRADE_LOCAL (Kinds.lua loads first)
Tags.CHAT_TAGS = { say = "S", yell = "Y", whisper = "W", bnet = "W", party = "P", instance = "I",
                   raid = "R", warning = "RW", guild = "G", officer = "O" }
Tags.TAG_LETTERS = 6
-- Group chat by the channel type in the line's link.
Tags.TYPES = { GUILD = "G", OFFICER = "O", PARTY = "P", RAID = "R", INSTANCE_CHAT = "I" }
Tags.TYPE_KINDS = { GUILD = "guild", OFFICER = "officer", PARTY = "party", RAID = "raid", INSTANCE_CHAT = "instance" }
-- Leaders share their group's link; the event tells them apart.
Tags.LEADERS = { CHAT_MSG_PARTY_LEADER = "PL", CHAT_MSG_RAID_LEADER = "RL", CHAT_MSG_INSTANCE_CHAT_LEADER = "IL" }
-- Speech by event: the game's format (CHAT_<key>_GET), the short tag, and the
-- kind whose custom tag overrides it.
Tags.SPEECH = {
    CHAT_MSG_SAY = { "SAY", "S", "say" }, CHAT_MSG_YELL = { "YELL", "Y", "yell" },
    CHAT_MSG_WHISPER = { "WHISPER", "W", "whisper" }, CHAT_MSG_WHISPER_INFORM = { "WHISPER_INFORM", "To" },
    CHAT_MSG_BN_WHISPER = { "BN_WHISPER", "W", "bnet" }, CHAT_MSG_BN_WHISPER_INFORM = { "BN_WHISPER_INFORM", "To" },
    CHAT_MSG_RAID_WARNING = { "RAID_WARNING", "RW", "warning" },
}

local function secret(v) return issecretvalue and issecretvalue(v) end
local function esc(s) return (string.gsub(s, "%p", "%%%0")) end

-- gsub replacements built once rather than a closure per line, since every chat
-- line comes through here. The current line's event and speech tag are passed in
-- through these two.
local lineEvent, lineTag

-- A line's tag. Communities have different names in the channel list and on their
-- lines, so if the name finds nothing, look it up by channel number.
local function ownTag(num, name)
    if not next(Tags.own) then return nil end
    local Kinds = ns.Kinds
    local tag = Tags.own[Kinds.OfChannel(string.match(name, "^(.-) %- ") or name)]
    if tag or not num then return tag end
    for _, c in ipairs(Kinds.Joined()) do
        if tostring(c.id) == num then return Tags.own[c.kind] end
    end
    return nil
end

-- "[1. General - Zone]"
local function channel(open, inner, close)
    local num, name = string.match(inner, "^(%d+)%. (.+)$")
    name = name or inner
    local base = string.gsub(string.gsub(string.match(name, "^(.-) %- ") or name, "%s+%d+$", ""), "%s", "")
    local tag = ownTag(num, name) or Tags.CHANNELS[base]
    if tag and num and Tags.numbers then tag = num .. ". " .. tag end
    return open .. "[" .. (tag or num or name) .. "]" .. close
end

-- "[Guild]", "[Party Leader]"...
local function group(open, ctype, _, close)
    local own = Tags.own[Tags.TYPE_KINDS[ctype]]
    local leader = Tags.LEADERS[lineEvent]
    local tag = (own and (leader and own .. "L" or own)) or leader or Tags.TYPES[ctype]
    if not tag then return nil end
    return open .. "[" .. tag .. "]" .. close
end

-- "Name says: ", "To Name: "...
local function speech(link)
    return "[" .. lineTag .. "] " .. link .. ": "
end

-- The game's timestamp at the start of a line ("15:27 ", "15:27:32 ", "03:27 PM "),
-- tinted tan (Tags.stampColor, set in Tags.Apply from INK.LABEL).
Tags.STAMP = "^(%d%d?:%d%d:?%d?%d?%s?[AP]?M?) "
local function stamp(t) return Tags.stampColor .. t .. "|r " end

-- The global string name of a speech format ("CHAT_SAY_GET").
local formatNames = {}
local function formatName(kind)
    local name = formatNames[kind]
    if not name then
        name = "CHAT_" .. kind .. "_GET"
        formatNames[kind] = name
    end
    return name
end

-- A pattern for each of the game's speech formats, built once (false when a
-- format has no name in it).
local speechPatterns = {}
local function speechPattern(fmt)
    local p = speechPatterns[fmt]
    if p == nil then
        local pre, suf = string.match(fmt, "^(.-)%%s(.*)$")
        p = pre and (esc(pre) .. "(|H[^|]*|h.-|h)" .. esc(suf)) or false
        speechPatterns[fmt] = p
    end
    return p
end

-- The shortened line, or nil if there's nothing to shorten.
function Tags.Shorten(msg, event)
    if type(msg) ~= "string" or secret(msg) then return nil end
    local out = msg
    out = string.gsub(out, "(|Hchannel:channel:%d+|h)%[(.-)%](|h)", channel, 1)
    lineEvent = event
    out = string.gsub(out, "(|Hchannel:(%u[%u_]*)|h)%[(.-)%](|h)", group, 1)
    lineEvent = nil
    local sp = Tags.SPEECH[event]
    local fmt = sp and _G[formatName(sp[1])]
    if type(fmt) == "string" then
        local pattern = speechPattern(fmt)
        if pattern then
            lineTag = Tags.own[sp[3]] or sp[2]
            out = string.gsub(out, pattern, speech, 1)
            lineTag = nil
        end
    end
    if Tags.stampColor then out = string.gsub(out, Tags.STAMP, stamp, 1) end
    return out ~= msg and out or nil
end

-- What a line gets: short tags (shortTags) and the speaker's level (levels,
-- Levels.lua). The changed line, or nil.
function Tags.Shape(msg, event)
    if type(msg) ~= "string" or secret(msg) then return nil end
    local out = Tags.enabled and Tags.Shorten(msg, event) or msg
    local Levels = ns.Levels
    if Levels and Levels.on then out = Levels.Mark(out) end
    return out ~= msg and out or nil
end

function Tags.Own(kind) return Tags.own[kind] end

-- Fallback tag for a channel: its word, else its number.
function Tags.Standard(name, id)
    local base = string.gsub(string.gsub(string.match(name, "^(.-) %- ") or name, "%s+%d+$", ""), "%s", "")
    return Tags.CHANNELS[base] or tostring(id)
end

-- Brackets and pipes would break the line's link. Empty means the standard tag.
function Tags.SetOwn(kind, text)
    local clean = string.gsub(string.gsub(text or "", "[|%[%]]", ""), "^%s*(.-)%s*$", "%1")
    local tags = {}
    for k, v in pairs(Tags.own) do tags[k] = v end
    tags[kind] = clean ~= "" and clean or nil
    Tags.own = tags
    DaylightUI:Set("Chat", "channelTags", tags)
end

-- Chat is locked down in raid, battleground and arena fights, and in Mythic+.
-- Lines are left alone there.
function Tags.Protected()
    if type(IsInInstance) ~= "function" then return false end
    local _, kind = IsInInstance()
    if secret(kind) then return true end
    if (kind == "raid" or kind == "pvp" or kind == "arena") and InCombatLockdown() then return true end
    local CM = C_ChallengeMode
    if kind == "party" and type(CM) == "table" and type(CM.IsChallengeModeActive) == "function"
        and CM.IsChallengeModeActive() then return true end
    return false
end

-- History entries already processed (the game's own tables, used only as keys).
local seen = setmetatable({}, { __mode = "k" })
-- Cap on entries processed per redraw (a full window after login).
Tags.SWEEP = 200

-- A history entry's event: the 4th value after its color, matching
-- AddMessage(msg, r, g, b, id, accessID, typeID, event, ...).
local function eventOf(e)
    local x = e.extraData
    local ev = type(x) == "table" and x[4]
    if secret(ev) or type(ev) ~= "string" then return nil end
    return ev
end

local changed = {}
-- The window just redrew. Shorten every entry added since the last redraw
-- (newest first, stopping at the first one already seen) and update its line.
function Tags.OnRedraw(cf)
    if not (Tags.enabled or (ns.Levels and ns.Levels.on)) then return end
    local hb = cf.historyBuffer
    if type(hb) ~= "table" or type(hb.GetEntryAtIndex) ~= "function" then return end
    local e = hb:GetEntryAtIndex(1)
    if type(e) ~= "table" or seen[e] then return end
    if Tags.IsCombatLog(cf) then return end
    local locked, any = Tags.Protected(), false
    for i = 1, Tags.SWEEP do
        if i > 1 then e = hb:GetEntryAtIndex(i) end
        if type(e) ~= "table" or seen[e] then break end
        seen[e] = true
        local m = e.message
        local short = not locked and not secret(m) and Tags.Shape(m, eventOf(e))
        if short then
            e.message = short
            changed[e], any = short, true
        end
    end
    if not any then return end
    local lines = cf.visibleLines
    if type(lines) == "table" then
        for _, line in ipairs(lines) do
            local short = changed[line.messageInfo]
            if short then line:SetText(short) end
        end
    end
    wipe(changed)
end

function Tags.IsCombatLog(cf)
    if cf == _G.COMBATLOG then return true end
    if type(IsCombatLog) == "function" then
        local ok, r = pcall(IsCombatLog, cf)
        if ok and r == true then return true end
    end
    return false
end

local watched = setmetatable({}, { __mode = "k" })
-- Called from Chat.Pass only, never from inside the game's code.
function Tags.Watch(cf)
    if watched[cf] or type(cf.AddOnDisplayRefreshedCallback) ~= "function" or Tags.IsCombatLog(cf) then return end
    watched[cf] = true
    cf:AddOnDisplayRefreshedCallback(function(f) DaylightUI.SafeCall(Tags.OnRedraw, f) end)
end

function Tags.Apply(cfg)
    Tags.enabled = cfg.shortTags and true or false
    Tags.numbers = cfg.channelNumbers and true or false
    Tags.own = type(cfg.channelTags) == "table" and cfg.channelTags or {}
    -- A tag set on a since-renamed kind (Kinds.RENAMED) moves to the new name.
    for old, real in pairs(ns.Kinds and ns.Kinds.RENAMED or {}) do
        if Tags.own[old] then
            local tags = {}
            for k, v in pairs(Tags.own) do tags[k] = v end
            tags[real], tags[old] = tags[real] or tags[old], nil
            Tags.own = tags
        end
    end
    local c = DaylightUI.Style.INK.LABEL
    Tags.stampColor = string.format("|cff%02x%02x%02x", c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5)
end
