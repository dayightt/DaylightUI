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
local secret = DaylightUI.IsSecret

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
                  ["Comercio(Servicios)"] = "TS", ["Comercio(Local)"] = "TL", Comerciolocal = "TL",
                  -- German clients name them in German.
                  Allgemein = "G", Handel = "T", LokaleVerteidigung = "LD", SucheNachGruppe = "LFG" }
-- Custom tags per channel or chat kind come from the channelTags setting (keyed by
-- kind, written whole, set in the chat options, Options.lua). A custom tag wins;
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
Tags.TYPE_KINDS = { GUILD = "guild", OFFICER = "officer", PARTY = "party", RAID = "raid", INSTANCE_CHAT = "instance" }
-- Leaders share their group's link; the event tells them apart. Each entry holds
-- its event, kind, parent kind, parent word and leader word, all read from game constants.
Tags.LEADERS = {
    { event = "CHAT_MSG_PARTY_LEADER", kind = "party_leader", parent = "party", word = "CHAT_MSG_PARTY", leader = "CHAT_MSG_PARTY_LEADER" },
    { event = "CHAT_MSG_RAID_LEADER", kind = "raid_leader", parent = "raid", word = "CHAT_MSG_RAID", parentAlias = "RAID", leader = "CHAT_MSG_RAID_LEADER" },
    { event = "CHAT_MSG_INSTANCE_CHAT_LEADER", kind = "instance_leader", parent = "instance", word = "CHAT_MSG_INSTANCE_CHAT", leader = "CHAT_MSG_INSTANCE_CHAT_LEADER" },
}
-- Speech by event: the game's format (CHAT_<key>_GET), the short tag, and the
-- kind whose custom tag overrides it.
Tags.SPEECH = {
    CHAT_MSG_SAY = { "SAY", "say", "say" }, CHAT_MSG_YELL = { "YELL", "yell", "yell" },
    CHAT_MSG_WHISPER = { "WHISPER", "whisper", "whisper" }, CHAT_MSG_WHISPER_INFORM = { "WHISPER_INFORM", "to" },
    CHAT_MSG_BN_WHISPER = { "BN_WHISPER", "bnet", "bnet" }, CHAT_MSG_BN_WHISPER_INFORM = { "BN_WHISPER_INFORM", "to" },
    CHAT_MSG_RAID_WARNING = { "RAID_WARNING", "warning", "warning" },
}

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
    -- The channel list by number, kept until channels change.
    local kind = Kinds.OfNumber(tonumber(num))
    return kind and Tags.own[kind] or nil
end

-- A name as pieces ("DefensaLocal" -> Defensa, Local) of UTF-8 characters; long is over two.
local function pieces(name)
    local text = string.gsub(name, "(%l)(%u)", "%1 %2")
    text = string.gsub(string.gsub(text, "[%(%)%-:%d]", " "), "%s+", " ")
    local out = {}
    for w in string.gmatch(text, "%S+") do
        local chars = {}
        for c in string.gmatch(w, "[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = c end
        if #chars > 0 then out[#out + 1] = { chars = chars, long = #chars > 2 } end
    end
    return out
end

-- The tags a name can take, best first: the initials of its long words, else its
-- first one, two and three letters.
local function candidates(name)
    if type(name) ~= "string" or secret(name) then return {} end
    local list = pieces(name)
    local long = {}
    for _, p in ipairs(list) do if p.long then long[#long + 1] = p end end
    if #long == 0 then long = list end
    local out = {}
    if #long > 1 then
        local t = {}
        for _, p in ipairs(long) do t[#t + 1] = string.upper(p.chars[1]) end
        out[#out + 1] = table.concat(t)
    end
    local first = long[1]
    if first then
        for n = 1, math.min(3, #first.chars) do
            local t = { string.upper(first.chars[1]) }
            for i = 2, n do t[#t + 1] = first.chars[i] end
            local tag = table.concat(t)
            if out[#out] ~= tag then out[#out + 1] = tag end
        end
    end
    return out
end

-- A name's best tag: "DefensaLocal" -> DL, "Comercio local" -> CL, "General" -> G.
function Tags.Initials(name)
    return candidates(name)[1]
end

-- Each chat kind's default tag comes from the game's own word for it. When two start
-- the same, the first in CHAT_ORDER keeps the short one (Hermandad H, Grupo G, Gritar
-- Gr). No word: its English letter (CHAT_TAGS). English words give the English letters.
Tags.CHAT_WORDS = { guild = "CHAT_MSG_GUILD", party = "CHAT_MSG_PARTY", raid = "CHAT_MSG_RAID",
                    say = "CHAT_MSG_SAY", whisper = "WHISPER", yell = "CHAT_MSG_YELL",
                    instance = "CHAT_MSG_INSTANCE_CHAT", officer = "CHAT_MSG_OFFICER",
                    warning = "CHAT_MSG_RAID_WARNING" }
Tags.CHAT_ORDER = { "guild", "party", "raid", "say", "whisper", "yell", "instance", "officer", "warning" }

local defaults, leaderDefaults
function Tags.ResetDefaults() defaults, leaderDefaults = nil, nil end

local function nonLatin(s)
    return type(s) == "string" and string.find(s, "[\128-\255]") ~= nil
end

local function firstText(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "string" and value ~= "" and not secret(value) then return value end
    end
end

local function leaderWord(leader)
    if leader.parent == "instance" then
        return firstText(_G.CHAT_MSG_INSTANCE_CHAT_LEADER, _G.INSTANCE_CHAT_LEADER)
    end
    return _G[leader.leader]
end

local function leaderTag(leader, nativeWord)
    if not nativeWord then return nil end
    local parentWord
    for _, name in ipairs({ Tags.CHAT_WORDS[leader.parent], leader.word, leader.parentAlias }) do
        if nonLatin(_G[name]) then parentWord = _G[name]; break end
    end
    if leader.parent == "instance" and not nonLatin(parentWord) then parentWord = firstText(_G.CHAT_MSG_INSTANCE_CHAT, _G.INSTANCE_CHAT) end
    if not nonLatin(parentWord) or not nonLatin(nativeWord) then return nil end
    local title = string.match(nativeWord, "^" .. esc(parentWord) .. "([^\128-\191].*)$")
    return title ~= "" and title or nil
end

local function nativeLeaderTags()
    if not leaderDefaults then
        local out, seen, duplicates = {}, {}, {}
        for _, leader in ipairs(Tags.LEADERS) do
            local tag = leaderTag(leader, leaderWord(leader))
            if tag then
                if seen[tag] then duplicates[tag] = true end
                seen[tag] = true
                out[leader.kind] = tag
            end
        end
        for _, leader in ipairs(Tags.LEADERS) do
            if duplicates[out[leader.kind]] then out[leader.kind] = nil end
        end
        leaderDefaults = out
    end
    return leaderDefaults
end

local function built()
    -- The game's own words (see above), unless the English letters are asked for.
    local out, used = {}, {}
    for _, kind in ipairs(Tags.CHAT_ORDER) do
        local word = _G[Tags.CHAT_WORDS[kind]]
        local pick
        for _, tag in ipairs(candidates(word)) do
            if not used[tag] then pick = tag; break end
        end
        pick = pick or Tags.CHAT_TAGS[kind]
        used[pick] = true
        out[kind] = pick
    end
    out.bnet = out.whisper
    -- Your own whispers: the word the game puts before the name ("To Name:", "A Name:").
    local fmt = _G.CHAT_WHISPER_INFORM_GET
    local pre = type(fmt) == "string" and not secret(fmt) and string.match(fmt, "^(.-)%%s")
    pre = pre and string.gsub(pre, "^%s*(.-)%s*$", "%1")
    -- A word too long for a tag ("你悄悄地对" on a Chinese client is the whole phrase) is "To".
    if pre and #(string.gsub(pre, "[\128-\191]", "")) > 4 then pre = nil end
    out.to = (pre and pre ~= "" and pre) or "To"
    return out
end

-- The tag letters setting: "native" (the default for new profiles: the initials of the game's words
-- in the player's language) or "english" (the letters Daylight UI has always used, kept for the
-- profiles that existed before).
function Tags.Native() return Tags.letters == "native" end

-- A chat kind's default tag; "to" is your sent whispers.
function Tags.Default(kind)
    if not Tags.Native() then return Tags.CHAT_TAGS[kind] or (kind == "to" and "To") or nil end
    defaults = defaults or built()
    return defaults[kind]
end

-- A world channel's standard tag. The game's id decides when it has one (the same in every
-- language). In English letters that is the kind's own tag (KIND_TAGS); in the player's language it is
-- the initials of the name the game gives that channel. Otherwise the channel's name decides, in any
-- letter case. The channel's kind isn't used there: World Defense and Newcomer share a kind with
-- Local Defense and General but have their own tags.
local ofName = {}
function Tags.ResetNames() if next(ofName) then ofName = {} end end

-- Tags.CHANNELS by lower-case word, built on first use.
local byWord
local function standardByName(base)
    if not byWord then
        byWord = {}
        for k, v in pairs(Tags.CHANNELS) do byWord[string.lower(k)] = v end
    end
    return byWord[string.lower(base)]
end

function Tags.OfName(name)
    if type(name) ~= "string" or secret(name) then return nil end
    local base = string.match(name, "^(.-) %- ") or name
    local zone = ns.Kinds.OfZone(base)
    if zone and Tags.Native() then
        local tag = ofName[name]
        if tag == nil then
            tag = Tags.Initials((string.gsub(string.gsub(base, "%s*:.*$", ""), "%s+%d+$", ""))) or false
            ofName[name] = tag
        end
        return tag or Tags.KIND_TAGS[zone]
    end
    if zone then return Tags.KIND_TAGS[zone] end
    return standardByName((string.gsub(string.gsub(base, "%s+%d+$", ""), "%s", "")))
end

-- The channel's words, as far as the "]|h" that closes them. A chat addon like Prat
-- draws "[G] |h" with the space inside the link, so the first "]|h" in the line
-- can belong to an item link further on: then the match holds a "|h" and the line
-- is left as it is, or the tag would swallow everything up to that link.
local function crossesLink(inner) return string.find(inner, "|h", 1, true) ~= nil end

-- "[1. General - Zone]"
local function channel(open, inner, close)
    if crossesLink(inner) then return nil end
    local num, name = string.match(inner, "^(%d+)%. (.+)$")
    name = name or inner
    local base = string.gsub(string.gsub(string.match(name, "^(.-) %- ") or name, "%s+%d+$", ""), "%s", "")
    local tag = ownTag(num, name) or Tags.OfName(name) or Tags.CHANNELS[base]
    if tag and num and Tags.numbers then tag = num .. ". " .. tag end
    return open .. "[" .. (tag or num or name) .. "]" .. close
end

-- "[Guild]", "[Party Leader]"...
local function group(open, ctype, inner, close)
    if crossesLink(inner) then return nil end
    local kind = Tags.TYPE_KINDS[ctype]
    if not kind then return nil end
    local leader
    for _, entry in ipairs(Tags.LEADERS) do
        if entry.event == lineEvent and entry.parent == kind then leader = entry; break end
    end
    local base = Tags.own[kind] or Tags.Default(kind)
    if not base then return nil end
    local tag = base
    if leader then
        local native = Tags.Native() and (not Tags.own[kind] or nonLatin(Tags.own[kind]))
        local localized = native and nativeLeaderTags()[leader.kind]
        tag = localized or base .. "L"
    end
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
            lineTag = Tags.own[sp[3]] or Tags.Default(sp[2])
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
    if Tags.quote then out = Tags.Each(out) end
    return out ~= msg and out or nil
end

-- ---------------------------------------------------------------------
-- The price of each one on a won commodity auction
-- ---------------------------------------------------------------------

-- The game's line says what you won and how many ("You won an auction for Linen
-- Cloth x14"), never what it cost. The client quotes the total just before the
-- buy goes through (COMMODITY_PRICE_UPDATED), so the line gets that total split
-- by the count. The quote is kept only for the frame its line arrives in: the
-- Daylight box and the game's redraw both read that one line, and no later line
-- can pick up an old price.
local usedAt
local patterns = {}

-- The game's format as a pattern, and which capture holds the count. Handles
-- positional holes ("%2$d") too, as some languages order them differently.
local function wonPattern(fmt)
    if patterns[fmt] ~= nil then return patterns[fmt][1], patterns[fmt][2] end
    local out, caps, countAt, i = {}, 0, nil, 1
    while true do
        local s, e, pos, kind = string.find(fmt, "%%(%d*)%$?([sd])", i)
        out[#out + 1] = esc(string.sub(fmt, i, s and s - 1 or #fmt))
        if not s then break end
        caps = caps + 1
        if kind == "d" then countAt = caps end
        out[#out + 1] = kind == "d" and "(%d+)" or "(.-)"
        i = e + 1
    end
    local pat = countAt and (table.concat(out) .. "$") or false
    patterns[fmt] = { pat, countAt }
    return pat, countAt
end

-- The line with " (3s 45c each)" added, or the line as it was.
function Tags.Each(msg)
    if not Tags.quote or type(msg) ~= "string" or secret(msg) then return msg end
    local now = GetTime()
    if usedAt and usedAt ~= now then Tags.quote, usedAt = nil, nil; return msg end
    local fmt = _G.ERR_AUCTION_COMMODITY_WON_S
    if type(fmt) ~= "string" then return msg end
    local pat, at = wonPattern(fmt)
    if not pat then return msg end
    -- Any other line matches nothing, and select() then hands tonumber no value at all.
    local caps = { string.match(msg, pat) }
    local count = caps[at] and tonumber(caps[at])
    if not count then return msg end
    usedAt = now
    if count < 2 then return msg end
    local each = math.floor(Tags.quote / count + 0.5)
    return msg .. " " .. string.format(DaylightUI.L["(%s each)"], DaylightUI.Widgets.Money(each))
end

local function onQuote(_, _, total)
    usedAt = nil
    Tags.quote = (type(total) == "number" and not secret(total) and total > 0) and total or nil
end
local function forget() Tags.quote, usedAt = nil, nil end

function Tags.ListenQuotes()
    if Tags.quoting then return end
    Tags.quoting = true
    DaylightUI.RegisterEvent("COMMODITY_PRICE_UPDATED", onQuote)
    DaylightUI.RegisterEvent("COMMODITY_PURCHASE_FAILED", forget)
    DaylightUI.RegisterEvent("AUCTION_HOUSE_CLOSED", forget)
end

function Tags.Own(kind) return Tags.own[kind] end

-- Fallback tag for a channel: its word, else its number.
function Tags.Standard(name, id)
    local base = string.gsub(string.gsub(string.match(name, "^(.-) %- ") or name, "%s+%d+$", ""), "%s", "")
    return Tags.OfName(name) or Tags.CHANNELS[base] or tostring(id)
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
    if not (Tags.enabled or (ns.Levels and ns.Levels.on) or Tags.quote) then return end
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
    Tags.ListenQuotes()
    -- The letters of the defaults: the game's words in the player's language, or the English ones.
    local letters = cfg.tagLetters == "native" and "native" or "english"
    if letters ~= Tags.letters then Tags.letters = letters; Tags.ResetDefaults(); Tags.ResetNames() end
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
