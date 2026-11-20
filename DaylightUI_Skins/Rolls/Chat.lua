-- Reads the game's loot roll chat lines: who picked what, every roll number and
-- the winner. The patterns are built from the game's own strings when the UI
-- loads, so every language works, including those whose strings put the holes in
-- another order (%2$s). Most lines start with the drop's Loot History id, which
-- tells two copies of the same item apart.

local _, ns = ...
local DUI = DaylightUI

local RollChat = {}
ns.RollChat = RollChat
DUI.RollChat = RollChat   -- the chat reads roll lines with it too (whose roll is it)

-- Each form: the global string, what kind of line it is and what each of its
-- holes holds, in the English argument order (positional holes map onto these).
-- kinds: started, pick, roll, won, allpassed.
RollChat.FORMS = {
    { global = "LOOT_ROLL_STARTED", kind = "started", args = { "id", "link" } },
    { global = "LOOT_ROLL_NEED", kind = "pick", pick = "need", args = { "id", "who", "link" } },
    { global = "LOOT_ROLL_GREED", kind = "pick", pick = "greed", args = { "id", "who", "link" } },
    { global = "LOOT_ROLL_PASSED", kind = "pick", pick = "pass", args = { "id", "who", "link" } },
    { global = "LOOT_ROLL_DISENCHANT", kind = "pick", pick = "disenchant", args = { "who", "link" } },
    { global = "LOOT_ROLL_PASSED_AUTO", kind = "pick", pick = "pass", args = { "who", "link" } },
    { global = "LOOT_ROLL_PASSED_AUTO_FEMALE", kind = "pick", pick = "pass", args = { "who", "link" } },
    { global = "LOOT_ROLL_NEED_SELF", kind = "pick", pick = "need", self = true, args = { "id", "link" } },
    { global = "LOOT_ROLL_NEED_SELF_OFF_SPEC", kind = "pick", pick = "need", self = true, offSpec = true, args = { "id", "link" } },
    { global = "LOOT_ROLL_GREED_SELF", kind = "pick", pick = "greed", self = true, args = { "id", "link" } },
    { global = "LOOT_ROLL_DISENCHANT_SELF", kind = "pick", pick = "disenchant", self = true, args = { "id", "link" } },
    { global = "LOOT_ROLL_PASSED_SELF", kind = "pick", pick = "pass", self = true, args = { "id", "link" } },
    { global = "LOOT_ROLL_PASSED_SELF_AUTO", kind = "pick", pick = "pass", self = true, args = { "id", "link" } },
    { global = "LOOT_ROLL_ROLLED_NEED", kind = "roll", pick = "need", args = { "id", "roll", "link", "who" } },
    { global = "LOOT_ROLL_ROLLED_GREED", kind = "roll", pick = "greed", args = { "id", "roll", "link", "who" } },
    { global = "LOOT_ROLL_ROLLED_TRANSMOG", kind = "roll", pick = "transmog", args = { "id", "roll", "link", "who" } },
    { global = "LOOT_ROLL_ROLLED_DE", kind = "roll", pick = "disenchant", args = { "roll", "link", "who" } },
    { global = "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", kind = "roll", pick = "need", args = { "roll", "link", "who" } },
    { global = "LOOT_ROLL_LOST_ROLL", kind = "roll", self = true, args = { "id", "word", "roll", "link" } },
    { global = "LOOT_ROLL_WON", kind = "won", args = { "id", "who", "link" } },
    { global = "LOOT_ROLL_YOU_WON", kind = "won", self = true, args = { "id", "link" } },
    { global = "LOOT_ROLL_WON_NO_SPAM_NEED", kind = "won", pick = "need", args = { "id", "who", "roll", "link" } },
    { global = "LOOT_ROLL_WON_NO_SPAM_NEED_OFF_SPEC", kind = "won", pick = "need", offSpec = true, args = { "id", "who", "roll", "link" } },
    { global = "LOOT_ROLL_WON_NO_SPAM_GREED", kind = "won", pick = "greed", args = { "id", "who", "roll", "link" } },
    { global = "LOOT_ROLL_WON_NO_SPAM_DE", kind = "won", pick = "disenchant", args = { "id", "who", "roll", "link" } },
    { global = "LOOT_ROLL_WON_NO_SPAM_TRANSMOGRIFICATION", kind = "won", pick = "transmog", args = { "id", "who", "roll", "link" } },
    { global = "LOOT_ROLL_YOU_WON_NO_SPAM_NEED", kind = "won", pick = "need", self = true, args = { "id", "roll", "link" } },
    { global = "LOOT_ROLL_YOU_WON_NO_SPAM_NEED_OFF_SPEC", kind = "won", pick = "need", self = true, offSpec = true, args = { "id", "roll", "link" } },
    { global = "LOOT_ROLL_YOU_WON_NO_SPAM_GREED", kind = "won", pick = "greed", self = true, args = { "id", "roll", "link" } },
    { global = "LOOT_ROLL_YOU_WON_NO_SPAM_DE", kind = "won", pick = "disenchant", self = true, args = { "id", "roll", "link" } },
    { global = "LOOT_ROLL_YOU_WON_NO_SPAM_TRANSMOG", kind = "won", pick = "transmog", self = true, args = { "id", "roll", "link" } },
    { global = "LOOT_ROLL_ALL_PASSED", kind = "allpassed", args = { "id", "link" } },
}

local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"

-- A format string as an anchored Lua pattern. slots[n] is the argument the n-th
-- capture holds, so "%2$s ... %1$d" still reads each value by its meaning.
-- The last %s takes the rest of the line; earlier ones take as little as they can.
function RollChat.Pattern(fmt)
    local parts, slots, holes = {}, {}, {}
    local i, n, len = 1, 0, #fmt
    while i <= len do
        local c = fmt:sub(i, i)
        if c == "%" then
            local pos, kind, after = fmt:match("^(%d+)%$([sd])()", i + 1)
            if not kind then kind, after = fmt:match("^([sd])()", i + 1) end
            if kind then
                n = n + 1
                slots[#slots + 1] = tonumber(pos) or n
                parts[#parts + 1] = false
                holes[#holes + 1] = { at = #parts, kind = kind }
                i = after
            else
                -- "%%" and anything else: the character itself.
                local nextc = fmt:sub(i + 1, i + 1)
                parts[#parts + 1] = (nextc ~= "" and nextc or "%"):gsub(MAGIC, "%%%0")
                i = i + (nextc ~= "" and 2 or 1)
            end
        else
            parts[#parts + 1] = (c:gsub(MAGIC, "%%%0"))
            i = i + 1
        end
    end
    local lastS
    for _, h in ipairs(holes) do if h.kind == "s" then lastS = h end end
    for _, h in ipairs(holes) do
        parts[h.at] = h.kind == "d" and "(%d+)" or (h == lastS and "(.+)" or "(.-)")
    end
    return "^" .. table.concat(parts) .. "$", slots
end

-- The literal text of a form, for ordering: longer, more specific forms are tried
-- first, so "You won: X" isn't read as "%s won: %s" by someone called "You".
local function literalLength(fmt)
    return #(fmt:gsub("%%%d+%$[sd]", ""):gsub("%%[sd]", ""))
end

local built = {}

function RollChat.Build()
    built = {}
    for index, form in ipairs(RollChat.FORMS) do
        local fmt = _G[form.global]
        if type(fmt) == "string" then
            local pattern, slots = RollChat.Pattern(fmt)
            built[#built + 1] = { form = form, pattern = pattern, slots = slots, size = literalLength(fmt), index = index }
        end
    end
    table.sort(built, function(a, b)
        if a.size ~= b.size then return a.size > b.size end
        return a.index < b.index
    end)
end

-- "Need" / "Greed" / ... as the game writes them, back to a pick.
local function pickOfWord(word)
    if word == _G.NEED then return "need" end
    if word == _G.GREED then return "greed" end
    if word == _G.ROLL_DISENCHANT then return "disenchant" end
    if word == _G.TRANSMOGRIFICATION then return "transmog" end
end

-- Other realms' players come as "Name-Realm".
local function cutRealm(who)
    return (who:gsub("%-[^%s%-]+$", ""))
end

-- One chat line, read: { kind, pick, who, self, link, roll, historyID, offSpec },
-- or nil for a secret line (the client's chat lockdown) or any other line.
function RollChat.Parse(text)
    if issecretvalue and issecretvalue(text) then return nil end
    if type(text) ~= "string" then return nil end
    for _, b in ipairs(built) do
        local caps = { text:match(b.pattern) }
        if caps[1] ~= nil then
            local form = b.form
            local line = { kind = form.kind, pick = form.pick, self = form.self or nil, offSpec = form.offSpec or nil }
            for c, value in ipairs(caps) do
                local role = form.args[b.slots[c]]
                if role == "id" then line.historyID = tonumber(value)
                elseif role == "roll" then line.roll = tonumber(value)
                elseif role == "link" then line.link = value
                elseif role == "who" then line.who = cutRealm(value)
                elseif role == "word" then line.pick = pickOfWord(value) end
            end
            return line
        end
    end
    return nil
end

-- A name's first word (the key a roll's players are kept under) and the whole name.
function RollChat.Names(who)
    if type(who) ~= "string" then return nil, nil end
    return who:match("^(%S+)") or who, who
end

RollChat.Build()
DUI.On("Login", function() DUI.SafeCall(RollChat.Build) end)
