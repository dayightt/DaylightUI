local _, DUI = ...
local Style = DUI.Style

-- One look for every tooltip, both the ones we build and the game's that get
-- repainted (Tooltip module's Tip.PaintSpell):
--   title    INK.TITLE white, or the thing's own color (quality, quest
--            difficulty, class): Tips.Title(text, r, g, b)
--   sub      INK.LABEL tan, the short line under a title (level, zone,
--            "Channeled", cast time, range)
--   line     label INK.TEXT, value INK.VALUE or colored by meaning
--   text     INK.TEXT soft white, for sentences and descriptions
--   hint     the click ("Click:") in the accent, what it does in INK.TEXT
--   numbers  in a sentence, by meaning (Tips.Numbers): heal GOOD, damage
--            DAMAGE, mana/rage/energy their power color, else the accent
-- Nothing else picks its own color. The accent is read at flush and is one
-- color for every row (for a gradient accent, its middle; sweeping it down
-- the rows looked like a rainbow).
-- Usage: Tips.Clear(), add rows, Tips.Flush(tooltip), then Show.
local Tips = {}
DUI.Tips = Tips

local INK = Style.INK
Tips.TITLE = INK.TITLE -- title, white
Tips.VALUE = INK.VALUE -- a number or a name, white
Tips.TEXT = INK.TEXT -- a sentence, a line's label, what a click does: soft white
Tips.LABEL = INK.LABEL -- a sub line or short line, tan
Tips.GOOD = INK.GOOD     -- done, whole
Tips.WARN = INK.WARN -- in progress, running low
Tips.BAD = INK.BAD -- not started, nearly out
Tips.MONEY = INK.MONEY   -- gold
Tips.HINT = 0.8 -- a hint ("Click: ..."), the accent slightly dimmed

local rows = {}
local ACCENT = { person = true, hint = true } -- rows that take an accent color
local function add(r) rows[#rows + 1] = r end

-- Drops rows left over from a build that errored halfway.
function Tips.Clear() wipe(rows) end
-- White, or a color that means something (a quest's difficulty).
function Tips.Title(text, r, g, b) add({ "title", text, type(r) == "number" and { r, g, b } or nil }) end
-- A short line under the title (level and zone), as a label.
function Tips.Sub(text) add({ "sub", text }) end
-- A soft white label with a white value (or color, a table, by meaning).
function Tips.Line(label, value, color) add({ "line", label, value or "", color or Tips.VALUE }) end
-- Someone in their class color (color), with where they are in the accent.
function Tips.Person(name, where, color) add({ "person", name, where or "", color or Tips.VALUE }) end
-- A wrapped sentence in soft white (or color, one that means something).
function Tips.Text(text, color) add({ "text", text, color or Tips.TEXT }) end
-- One click and what it does.
function Tips.Hint(text) add({ "hint", text }) end
function Tips.Gap() add({ "gap" }) end

-- The game's own tooltip colors by meaning: "yellow" (a spell's description),
-- "white" (cost, cast time, range...), "red" (an unmet requirement), nil for
-- a color of the thing's own (a quality) or none.
Tips.SHORT_LINE = 30 -- longer than this reads as a sentence, not a cast time or range
function Tips.GameColor(r, g, b)
    if type(r) ~= "number" or (issecretvalue and issecretvalue(r)) then return nil end
    if r > 0.9 and g > 0.7 and g < 0.9 and b < 0.2 then return "yellow" end
    if r > 0.95 and g > 0.95 and b > 0.95 then return "white" end
    if r > 0.9 and g < 0.3 and b < 0.3 then return "red" end
end

-- One side of a game tooltip line, repainted to our rules (Tip.PaintSpell
-- does the same for the game's lines). The yellow description becomes a
-- sentence with colored numbers, a white cost takes its power color, other
-- short white lines become labels (long ones sentences), red becomes BAD, and
-- a line with its own color codes or color is left alone. Returns text, color.
function Tips.GameSide(text, c)
    if type(text) ~= "string" or text == "" then return text, Tips.TEXT end
    local r, g, b
    if type(c) == "table" and not (issecretvalue and issecretvalue(c)) then r, g, b = c.r or c[1], c.g or c[2], c.b or c[3] end
    local kind = Tips.GameColor(r, g, b)
    if text:find("|c", 1, true) then return text, kind and Tips.TEXT or { r, g, b } end
    if kind == "yellow" then return Tips.Numbers(text), Tips.TEXT end
    if kind == "red" then return text, Tips.BAD end
    if kind == "white" then
        local power = text:find("%d") and Tips.PowerIn(text)
        if power then return text, { Style.PowerColor(power) } end
        return Tips.Numbers(text), #text <= Tips.SHORT_LINE and Tips.LABEL or Tips.TEXT
    end
    if type(r) == "number" then return text, { r, g, b } end
    return Tips.Numbers(text), Tips.TEXT
end

-- A line of the game's tooltip data (C_TooltipInfo leftText/leftColor,
-- rightText/rightColor), painted by Tips.GameSide. Plain text only.
function Tips.GameLine(left, lc, right, rc)
    local lt, lcol = Tips.GameSide(left, lc)
    if type(right) == "string" and right ~= "" then
        local rt, rcol = Tips.GameSide(right, rc)
        add({ "pair", lt or "", rt, lcol, rcol })
    else
        add({ "text", lt or "", lcol })
    end
end

local function mix(a, b, f)
    return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
end

-- Progress have/need as a color: red at none, amber from halfway on (leaning
-- only slightly green), green when done. VALUE when there's nothing to count.
function Tips.Progress(have, need)
    if type(have) ~= "number" or type(need) ~= "number" or need <= 0 then return Tips.VALUE end
    local f = math.max(0, math.min(1, have / need))
    if f >= 1 then return Tips.GOOD end
    if f < 0.5 then return mix(Tips.BAD, Tips.WARN, f / 0.5) end
    return mix(Tips.WARN, Tips.GOOD, (f - 0.5) / 0.5 * 0.6)
end

-- Adds the rows to tip (GameTooltip by default) and empties the list.
-- opts.sweep = "daylight" uses the Daylight sweep whatever the accent (for the
-- options window, which always uses it).
function Tips.Flush(tip, opts)
    tip = tip or GameTooltip
    if not tip then wipe(rows) return end
    local daylight = type(opts) == "table" and opts.sweep == "daylight"
    local n, i = 0, 0
    for _, r in ipairs(rows) do
        if ACCENT[r[1]] then n = n + 1 end
    end
    for _, r in ipairs(rows) do
        local kind = r[1]
        if kind == "title" then
            local c = r[3] or Tips.TITLE
            tip:AddLine(r[2], c[1], c[2], c[3])
        elseif kind == "gap" then
            tip:AddLine(" ")
        elseif kind == "sub" then
            local L = Tips.LABEL
            tip:AddLine(r[2], L[1], L[2], L[3])
        elseif kind == "line" then
            local c, t = r[4], Tips.TEXT
            tip:AddDoubleLine(r[2], r[3], t[1], t[2], t[3], c[1], c[2], c[3])
        elseif kind == "text" then
            local c = r[3]
            tip:AddLine(r[2], c[1], c[2], c[3], true)
        elseif kind == "pair" then
            local a, b = r[4], r[5]
            tip:AddDoubleLine(r[2], r[3], a[1], a[2], a[3], b[1], b[2], b[3])
        else
            i = i + 1
            local t = nil -- one accent color for every row; sweeping it down the rows looked like a rainbow
            local ar, ag, ab
            if daylight then ar, ag, ab = Style.SweepAt(t) else ar, ag, ab = Style.AccentAt(t) end
            local c = r[4]
            if kind == "hint" then
                -- the click in the accent and what it does in calm text, so they read apart
                local key, what = r[2]:match("^(.-:)(%s.*)$")
                local L = Tips.TEXT
                if key then
                    tip:AddLine(DUI.Win.Parts.Hex({ ar, ag, ab }) .. key .. "|r" .. what, L[1], L[2], L[3])
                else
                    tip:AddLine(r[2], ar * Tips.HINT, ag * Tips.HINT, ab * Tips.HINT)
                end
            else
                tip:AddDoubleLine(r[2], r[3], c[1], c[2], c[3], ar, ag, ab)
            end
        end
    end
    wipe(rows)
end

-- Numbers in a sentence (spell descriptions, stat tooltips)

-- Each number in a sentence is colored by what it is: heals green (INK.GOOD),
-- damage soft red (INK.DAMAGE), mana/rage/energy in their power color, and
-- anything else in the accent (Style.Pop, read now). The kind comes from the
-- surrounding words, lowercased, in the client's language with English as the
-- fallback; a miss just stays the accent. A heal word must be in the gap
-- before the number, a damage word in the gap after, and a power word must be
-- the very next word. Linked numbers ("120 to 145") share one kind.
Tips.WORDS = {
    enUS = { heal = { "heal", "restor" }, damage = { "damage" }, link = { "to", "-" } },
    deDE = { heal = { "heil", "stellt" }, damage = { "schaden" }, link = { "bis", "-" } },
    frFR = { heal = { "soign", "rend" }, damage = { "dégâts" }, link = { "à", "-" } },
    esES = { heal = { "sana", "restaura" }, damage = { "daño" }, link = { "a", "-" } },
}
Tips.POWERS = { MANA = "MANA", RAGE = "RAGE", ENERGY = "ENERGY", FOCUS = "FOCUS" } -- the game's word globals -> power token

local function words()
    return Tips.WORDS[DUI.LOCALE] or Tips.WORDS.enUS
end
local function has(s, list)
    for _, w in ipairs(list) do if s:find(w, 1, true) then return true end end
end
-- The power a gap names (using the game's own word, so any language), or nil.
local function powerIn(s)
    for global, token in pairs(Tips.POWERS) do
        local w = _G[global]
        if type(w) == "string" and w ~= "" and s:find(string.lower(w), 1, true) then return token end
    end
end
Tips.PowerIn = function(s) return type(s) == "string" and powerIn(string.lower(s)) or nil end

-- The color for a number of this kind (nil kind means the accent).
function Tips.NumberColor(kind)
    if kind == "heal" then return INK.GOOD end
    if kind == "damage" then return INK.DAMAGE end
    if type(kind) == "string" and kind ~= "" then return { Style.PowerColor(kind) } end
    return { Style.Pop() }
end

-- The spans of the game's escape codes that carry digits of their own: the
-- plural and grammar codes (|4hour:hrs;), textures, atlases, links and key
-- names. A color code put inside one breaks it, so numbers there stay as they are.
local CODES = { "|%d[^;]*;", "|T.-|t", "|A.-|a", "|H.-|h", "|K.-|k" }
function Tips.CodeSpans(text)
    local spans
    if text:find("|", 1, true) then
        for _, p in ipairs(CODES) do
            local from = 1
            while true do
                local a, b = text:find(p, from)
                if not a then break end
                spans = spans or {}
                spans[#spans + 1] = { a, b }
                from = b + 1
            end
        end
    end
    return function(at)
        if spans then for _, s in ipairs(spans) do if at >= s[1] and at <= s[2] then return true end end end
        return false
    end
end

-- Returns text with its numbers colored. Only standalone numbers, and only on
-- a line without its own color codes (a |r would end that color early). Plain
-- strings only, never a secret.
function Tips.Numbers(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or text:find("|c", 1, true) then return text end
    local W = words()
    local low = string.lower(text)
    local nums = {}
    local inCode = Tips.CodeSpans(text)
    -- %f[%d], not %f[%w]: the game's text sometimes glues a number to the word
    -- before it ("inflicts32 to 35"), and that one gets its space back.
    for s, n, e in text:gmatch("()%f[%d](%d[%d,]*%.?%d*)()") do
        while n:sub(-1) == "." or n:sub(-1) == "," do n, e = n:sub(1, -2), e - 1 end -- trailing punctuation belongs to the sentence, not the number
        if not inCode(s) then
            nums[#nums + 1] = { s = s, e = e, n = n, glued = s > 1 and text:sub(s - 1, s - 1):find("%a") ~= nil }
        end
    end
    if #nums == 0 then return text end
    local dmg = W.damage
    if type(_G.DAMAGE) == "string" then dmg = { _G.DAMAGE:lower(), unpack(W.damage) } end
    for i, x in ipairs(nums) do
        local from = i > 1 and nums[i - 1].e or 1
        local to = i < #nums and nums[i + 1].s - 1 or #text
        -- gaps stop at the end of a sentence
        local before = low:sub(from, x.s - 1):match("[^%.;]*$") or ""
        local after = low:sub(x.e, to):match("^[^%.;]*") or ""
        x.gap = after
        -- a power only as the very next word ("50 Mana"). "20 health every second
        -- while you focus" is a heal, not Focus
        local nextWord = after:match("^%s*(%S+)") or ""
        if has(after, dmg) then x.kind = "damage"
        elseif powerIn(nextWord) then x.kind = powerIn(nextWord)
        elseif has(before, W.heal) then x.kind = "heal" end
    end
    -- "120 to 145": a short linking word between two numbers shares the kind
    for i = 1, #nums - 1 do
        local a, b = nums[i], nums[i + 1]
        local gap = a.gap:gsub("^%s+", ""):gsub("%s+$", "")
        local linked = false
        for _, w in ipairs(W.link) do if gap == w then linked = true end end
        if linked then
            local k = a.kind or b.kind
            a.kind, b.kind = k, k
        end
    end
    local out, at = {}, 1
    for _, x in ipairs(nums) do
        out[#out + 1] = text:sub(at, x.s - 1)
        if x.glued then out[#out + 1] = " " end
        out[#out + 1] = DUI.Win.Parts.Hex(Tips.NumberColor(x.kind)) .. x.n .. "|r"
        at = x.e
    end
    out[#out + 1] = text:sub(at)
    return table.concat(out)
end
