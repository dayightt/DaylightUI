-- Extras for the Daylight chat box, applied to a copy of each plain line in
-- Box.Feed. Secret lines are never inspected.
-- * Spam: in public channels (say, General, Trade, LFG, defense, custom channels;
--   never guild, group or whispers) drop repeats from the same person within
--   REPEAT seconds, gold-seller ads, and lines with any of your blocked words.
-- * Alerts: your name and chosen words are highlighted in the accent when others
--   talk (never your own lines, never a name or channel inside a link). An
--   unselected tab showing the line pulses, and with alertSound on a soft sound
--   plays, at most every PING seconds.
-- * Group finding: role words in "LF2M need a healer" lines get the game's role
--   icon, and "whisper" and "invite" links are added after the line.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style

local Extras = {}
ns.Extras = Extras

Extras.REPEAT = 60 -- seconds within which a repeat counts as spam
Extras.PING = 4 -- minimum seconds between alert sounds
Extras.PING_SOUND = "dewdrop"
Extras.LINK = "daylightchat" -- link type for our own links: |Hdaylightchat:spam:all|h

-- Channels where strangers talk, checked for spam.
Extras.PUBLIC = { say = true, yell = true, emote = true, general = true, trade = true, lfg = true, defense = true, channel = true }
function Extras.Public(kind) return Extras.PUBLIC[kind] or ns.Kinds.Own(kind) end
-- Channels where people talk, checked for alerts (whispers have their own sound).
Extras.TALK = { say = true, yell = true, general = true, trade = true, lfg = true, defense = true, channel = true,
                guild = true, officer = true, party = true, instance = true, raid = true, warning = true,
                [ns.Kinds.SERVICES] = true, [ns.Kinds.TRADE_LOCAL] = true }

Extras.ADVERTS = {
    "www%.", "https?:", "%.com%f[%W]", "%.net%f[%W]", "dot%s*com", "cheap%s+gold", "gold%s+for%s+sale",
    "buy%s+gold", "sell%s+gold", "%d+%%%s*off", "discount", "power%s*level", "fast%s+delivery",
    -- Match each currency sign as a whole sequence. They're multi-byte, and a
    -- character class of their bytes would match parts of Cyrillic or CJK letters.
    "%$%s*%d", "€%s*%d", "£%s*%d",
}

-- Role words and the icon put in front of each (W.RoleText, same art as the
-- group finder window).
Extras.ROLES = {
    { words = { "tanks", "tank" }, role = "TANK" },
    { words = { "healers", "healer", "heals", "heal", "healz" }, role = "HEALER" },
    { words = { "dps", "dd" }, role = "DAMAGER" },
}
Extras.ICON = 12 -- role icon size in a line

local cfg
local recent, recentCount = {}, 0
local lastPing = -math.huge

function Extras.Apply(c) cfg = c end

-- A line as read, lower-cased, without the game's timestamp.
local function plainLower(text)
    local p = ns.Copy.Plain(text)
    p = string.gsub(p, "^%s*%[?%d+:%d+:?%d*%s?[AaPp]?[Mm]?%]?%s*", "")
    return string.lower(p)
end

-- Is this line yours? Compare GUIDs (the event's arg12) first, which is exact
-- whatever form the name takes. Secret GUIDs aren't compared.
local function isMe(sender, guid)
    if type(guid) == "string" and not issecretvalue(guid) then
        local mine = UnitGUID("player")
        if type(mine) == "string" and not issecretvalue(mine) and guid == mine then return true end
    end
    if type(sender) ~= "string" then return false end
    local me = UnitName("player")
    if type(me) ~= "string" or issecretvalue(me) then return false end
    return sender == me or string.match(sender, "^([^%-]+)") == me
end

-- Calls fn on each piece of text outside links and textures.
local function outsideLinks(text, fn)
    local out, pos = {}, 1
    while true do
        local s, e = string.find(text, "|H.-|h.-|h", pos)
        local ts, te = string.find(text, "|[TA].-|[ta]", pos)
        if ts and (not s or ts < s) then s, e = ts, te end
        if not s then break end
        out[#out + 1] = fn(string.sub(text, pos, s - 1))
        out[#out + 1] = string.sub(text, s, e)
        pos = e + 1
    end
    out[#out + 1] = fn(string.sub(text, pos))
    return table.concat(out)
end

-- A plain word as a pattern, with magic characters escaped.
local function literal(word)
    return (string.gsub(word, "[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"))
end

-- Same, but case-insensitive.
local function anyCase(word)
    return (string.gsub(literal(word), "%a", function(ch) return "[" .. string.lower(ch) .. string.upper(ch) .. "]" end))
end

-- Word boundaries: bytes 128 and up (accented or non-Latin letters in UTF-8)
-- count as part of a word, so accented words match whole and never inside a
-- longer word. %w only covers English letters.
local WORD_IN, WORD_OUT = "%f[%w\128-\255]", "%f[^%w\128-\255]"

local function hex(r, g, b) return DUI.Win.Parts.Hex({ r, g, b }) end

-- ---------------------------------------------------------------------
-- Spam
-- ---------------------------------------------------------------------

-- Your blocked words and phrases, one per line in spamWords, as typed.
function Extras.SpamList()
    local list = {}
    for w in string.gmatch(DUI:Get("Chat", "spamWords") or "", "[^\n]+") do list[#list + 1] = w end
    return list
end

local function spamSave(list) DUI:Set("Chat", "spamWords", table.concat(list, "\n")) end

local function spamKey(word) return (string.gsub(string.lower(word), "%s+", " ")) end

-- False if there's nothing to add or it's already on the list.
function Extras.SpamAdd(word)
    word = string.match((string.gsub(word or "", "%s+", " ")), "^ ?(.-) ?$")
    if word == "" then return false end
    local list = Extras.SpamList()
    for _, w in ipairs(list) do
        if spamKey(w) == spamKey(word) then return false end
    end
    list[#list + 1] = word
    spamSave(list)
    return true
end

function Extras.SpamRemove(word)
    local list = Extras.SpamList()
    for i, w in ipairs(list) do
        if w == word then
            table.remove(list, i)
            spamSave(list)
            return
        end
    end
end

-- Word boundaries only work next to a letter or digit; "$$$" has none.
local function spamPattern(word)
    local p = literal(spamKey(word))
    if string.find(word, "^[%w\128-\255]") then p = WORD_IN .. p end
    if string.find(word, "[%w\128-\255]$") then p = p .. WORD_OUT end
    return p
end

-- Patterns are rebuilt only when the setting changes.
local spamFrom, spamPatterns
local function ownWords()
    local saved = cfg.spamWords or ""
    if saved ~= spamFrom then
        spamFrom, spamPatterns = saved, {}
        for w in string.gmatch(saved, "[^\n]+") do spamPatterns[#spamPatterns + 1] = spamPattern(w) end
    end
    return spamPatterns
end

-- body is what the person typed (arg1), not the whole line, so "trade" doesn't
-- match every Trade channel line, nor a name match its owner.
function Extras.IsSpam(kind, sender, text, guid, body)
    if not cfg or not Extras.Public(kind) or isMe(sender, guid) then return false end
    local lower = plainLower(text)
    if body then
        local said = string.gsub(plainLower(body), "%s+", " ")
        for _, p in ipairs(ownWords()) do
            if string.find(said, p) then return true end
        end
    end
    if cfg.spamAds ~= false then
        for _, p in ipairs(Extras.ADVERTS) do
            if string.find(lower, p) then return true end
        end
    end
    if cfg.spamRepeats ~= false and sender then
        local now = GetTime()
        local key = sender .. "\001" .. string.gsub(lower, "%s+", " ")
        local seen = recent[key]
        recent[key] = now
        if seen and now - seen < Extras.REPEAT then return true end
        recentCount = recentCount + 1
        if recentCount > 400 then
            for k, t in pairs(recent) do if now - t > Extras.REPEAT then recent[k] = nil end end
            recentCount = 0
        end
    end
    return false
end

-- ---------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------

function Extras.Words()
    local words = {}
    if not cfg then return words end
    for w in string.gmatch(cfg.alertWords or "", "[^,]+") do
        w = string.match(w, "^%s*(.-)%s*$")
        if #w >= 2 then words[#words + 1] = w end
    end
    if cfg.alertName ~= false then
        local me = UnitName("player")
        if type(me) == "string" and not issecretvalue(me) and me ~= "" then words[#words + 1] = me end
    end
    return words
end

local function alert(text, kind, sender, guid)
    if not Extras.TALK[kind] or isMe(sender, guid) then return text, false end
    local words = Extras.Words()
    if #words == 0 then return text, false end
    -- Only count words that actually lit up. The sender's name and the channel are
    -- links, so they never count.
    local on, lit = hex(Style.Accent()), 0
    text = outsideLinks(text, function(seg)
        for _, w in ipairs(words) do
            local n
            seg, n = string.gsub(seg, WORD_IN .. anyCase(w) .. WORD_OUT, on .. "%0|r")
            lit = lit + n
        end
        return seg
    end)
    if lit == 0 then return text, false end
    if cfg.alertSound == true then
        local now = GetTime()
        if now - lastPing >= Extras.PING then
            lastPing = now
            local file = ns.Whisper.SOUNDS[Extras.PING_SOUND]
            if file and type(PlaySoundFile) == "function" then PlaySoundFile(file, "SFX") end
        end
    end
    return text, true
end

-- ---------------------------------------------------------------------
-- Group finding
-- ---------------------------------------------------------------------

function Extras.LooksLikeGroup(lower)
    return string.find(lower, "%f[%w]lf%d*m%f[%W]") or string.find(lower, "%f[%w]lfg%f[%W]")
        or string.find(lower, "%f[%w]lf%f[%W]") or string.find(lower, "looking for")
        or (string.find(lower, "%f[%w]need%f[%W]") and (string.find(lower, "tank") or string.find(lower, "heal")
            or string.find(lower, "%f[%w]dps%f[%W]")))
end

-- Role words in color: tanks mana blue, healers green, damage soft red (the same
-- colors those words get in tooltip sentences).
function Extras.RoleColor(role)
    if role == "TANK" then return { Style.PowerColor("MANA") } end
    if role == "HEALER" then return Style.INK.GOOD end
    return Style.INK.DAMAGE
end

local function group(text, kind)
    if not (Extras.Public(kind) or kind == "party" or kind == "instance") then return text end
    if not Extras.LooksLikeGroup(plainLower(text)) then return text end
    -- Mark every role word first, then add icon and color in one pass, so an icon's
    -- own name is never matched as a word.
    return (outsideLinks(text, function(seg)
        for i, role in ipairs(Extras.ROLES) do
            for _, w in ipairs(role.words) do
                seg = string.gsub(seg, "%f[%w]" .. anyCase(w) .. "%f[%W]", "" .. i .. "%0")
            end
        end
        return (string.gsub(seg, "(%d)(.-)", function(i, word)
            local role = Extras.ROLES[tonumber(i)]
            return DUI.Widgets.RoleText(role.role, Extras.ICON) .. hex(unpack(Extras.RoleColor(role.role))) .. word .. "|r"
        end))
    end))
end

-- Our copy of a plain line with alert words lit and role icons added. Returns
-- true if it's an alert.
function Extras.Decorate(text, kind, sender, guid)
    if not cfg then return text, false end
    local hit
    text, hit = alert(text, kind, sender, guid)
    if cfg.groupLines ~= false then text = group(text, kind) end
    return text, hit
end

-- Handles a click on one of our links; true if it was ours. Old whisper or
-- invite links restored from history do nothing.
function Extras.OnLink(link)
    if type(link) ~= "string" or issecretvalue(link) then return false end
    local what = string.match(link, "^" .. Extras.LINK .. ":(%a+):.+$")
    if not what then return false end
    if what == "spam" then ns.Box.ShowSpam() end
    return true
end
