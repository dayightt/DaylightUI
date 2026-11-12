-- Whispers to names with non-English letters (accented, Chinese, Korean...).
-- The game turns "/w Name message" into a whisper by checking its name
-- autocomplete (friends, guild, nearby) and, if nothing matches, trimming words
-- off the end until one is left (ChatFrameEditBoxBaseMixin:ExtractTellTarget).
-- On WoW: Forever a two-word name with such letters then never becomes a whisper.
-- So a moment after a space is typed (heard through the box's OnKeyDown hook,
-- shared with Up/Down recall), a box still holding "/w First Last " with such a
-- letter is turned into the whisper the game would make: tell target, chat type,
-- remaining text and header, using the game's own methods like its
-- ProcessChatType does. Plain English names are left to the game.

local _, ns = ...

local Tell = {}
ns.Tell = Tell

-- Whisper slash commands: the usual ones plus the game's localized ones.
Tell.CMDS = { ["/w"] = true, ["/whisper"] = true, ["/t"] = true, ["/tell"] = true, ["/cw"] = true }
Tell.CHARACTER = { ["/cw"] = true } -- always a character name, never a Battle.net friend

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function nonAscii(s) return string.find(s, "[\128-\255]") ~= nil end

local function learnCommands()
    if Tell.learned then return end
    Tell.learned = true
    for _, key in ipairs({ "WHISPER", "SMART_WHISPER", "CHARACTER_WHISPER", "CHARWHISPER" }) do
        local i = 1
        while type(_G["SLASH_" .. key .. i]) == "string" do
            local cmd = string.lower(_G["SLASH_" .. key .. i])
            Tell.CMDS[cmd] = true
            if string.find(key, "CHAR", 1, true) then Tell.CHARACTER[cmd] = true end
            i = i + 1
        end
    end
end

-- Parses "/w First Last message" once the name is followed by a space. Returns
-- the target and message if the name has a non-English letter, else nil.
function Tell.Parse(text)
    learnCommands()
    local cmd, rest = string.match(text, "^(/%S+)%s+(.*)$")
    if not cmd then return nil end
    cmd = string.lower(cmd)
    if not Tell.CMDS[cmd] then return nil end
    local first, afterFirst = string.match(rest, "^(%S+)(.*)$")
    if not first then return nil end
    -- Every name is two words here, Chinese and Korean too (the client refuses one word).
    local second, tail = string.match(afterFirst, "^%s+(%S+)(.*)$")
    if not second then return nil end
    local body = string.match(tail, "^%s(.*)$")
    if not body then return nil end   -- still typing the last name
    if not nonAscii(first) and not nonAscii(second) then return nil end -- leave it to the game
    -- After /w the second word may already be the message, so it only counts as a
    -- last name when capitalized (or it has a non-English letter).
    if not Tell.CHARACTER[cmd] and not nonAscii(second) and string.find(second, "^%l") then return nil end
    return first .. " " .. second, body
end

-- Runs a moment after a space: converts the box to a whisper if it's one we handle.
function Tell.Check(eb)
    if type(eb) ~= "table" or type(eb.GetText) ~= "function" then return end
    local text = eb:GetText()
    if type(text) ~= "string" or secret(text) or string.sub(text, 1, 1) ~= "/" or not nonAscii(text) then return end
    local target, body = Tell.Parse(text)
    if not target then return end
    if eb.SetTellTarget then eb:SetTellTarget(target) else eb:SetAttribute("tellTarget", target) end
    if eb.SetChatType then eb:SetChatType("WHISPER") else eb:SetAttribute("chatType", "WHISPER") end
    eb:SetText(body)
    if eb.UpdateHeader then eb:UpdateHeader() end
end

local function onKey(eb, key)
    if key ~= "SPACE" then return end
    C_Timer.After(0, function() Tell.Check(eb) end)
end

local watched = setmetatable({}, { __mode = "k" })
function Tell.Watch(eb)
    if type(eb) ~= "table" or watched[eb] or type(eb.HookScript) ~= "function" then return end
    watched[eb] = true
    eb:HookScript("OnKeyDown", onKey)
end
