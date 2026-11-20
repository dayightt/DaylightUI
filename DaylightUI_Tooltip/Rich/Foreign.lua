-- Other addons' lines on the rich card: Auctionator, TSM, Questie, RaiderIO,
-- Pawn, bag counts, anything that adds to a tooltip. None of them has to do a
-- thing. Every line after the data's own (the game's) is another addon's, read
-- from the tooltip's own text each fill, with the money frames the game hangs
-- on a line. Daylight UI plugins' lines (the API) come with what they are, so
-- they draw as rows, bars, tags and tiles.
--
-- A small table per addon (Foreign.ADAPTERS) knows its lines by their shape,
-- not by the addon's name: quest rows, price rows, a score. Any other line gets
-- the plain repaint: left words soft white, right words white, a typed-in gray
-- the label tan, money as Daylight UI's coins, inline icons cropped, a blank
-- line a gap.
--
-- Where they go is a setting: their own area at the bottom of the card after a
-- rule, mixed in with the card's own rows, or not at all.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local isSecret = DUI.IsSecret
local L = DUI.L

local Foreign = {}
ns.RichForeign = Foreign

Foreign.GAP = 4 -- a blank line between two of an addon's lines

local function cfg() return ns.Tooltip.Config() or {} end

-- "own" (their own area, the default), "mixed" or "hidden".
function Foreign.Where()
    local w = cfg().addonLines
    if w == "mixed" or w == "hidden" then return w end
    return "own"
end

local function adapterOn(key)
    local list = cfg().addonAdapters
    return not (type(list) == "table" and list[key] == false)
end

-- ---------------------------------------------------------------------
-- Words
-- ---------------------------------------------------------------------

local function strip(t) return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function trim(t) return (t:gsub("^%s+", ""):gsub("%s+$", "")) end

-- A line with nothing to read: no words, or only spaces (the game's own
-- AddLine(" ") between parts, and the line a money frame sits on).
function Foreign.Blank(t)
    return t == nil or trim(strip(t)) == ""
end

-- A typed-in gray (|cff999999, |cff808080...): the same amount of red, green
-- and blue, neither dark nor white. It reads as a label, so it becomes tan.
local function grayHex(r, g, b)
    r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
    return math.abs(r - g) <= 16 and math.abs(g - b) <= 16 and r >= 0x50 and r <= 0xD8
end
function Foreign.Gray(c)
    if type(c) ~= "table" or type(c[1]) ~= "number" then return false end
    return math.abs(c[1] - c[2]) <= 0.07 and math.abs(c[2] - c[3]) <= 0.07 and c[1] >= 0.3 and c[1] <= 0.85
end

function Foreign.UnGray(t)
    local tan
    return (t:gsub("|c(%x%x)(%x%x)(%x%x)(%x%x)", function(a, r, g, b)
        if not grayHex(r, g, b) then return nil end
        tan = tan or DUI.Win.Parts.Hex(Style.INK.LABEL)
        return tan
    end))
end

-- Inline icons (|Tpath:h:w...|t) cropped like every icon of Daylight UI's
-- (Style.ICON_CROP), unless the line gave its own texture coordinates.
function Foreign.Crop(t)
    if not t:find("|T", 1, true) then return t end
    local c = Style.ICON_CROP
    local l, r, top, b = math.floor(c[1] * 100 + 0.5), math.floor(c[2] * 100 + 0.5),
        math.floor(c[3] * 100 + 0.5), math.floor(c[4] * 100 + 0.5)
    return (t:gsub("|T([^|]*)|t", function(body)
        local parts = {}
        for piece in (body .. ":"):gmatch("([^:]*):") do parts[#parts + 1] = piece end
        if #parts >= 7 then return nil end
        local h = parts[2] ~= nil and parts[2] ~= "" and parts[2] or "0"
        local w = parts[3] ~= nil and parts[3] ~= "" and parts[3] or h
        return string.format("|T%s:%s:%s:%s:%s:100:100:%d:%d:%d:%d|t", parts[1], h, w,
            parts[4] or "0", parts[5] or "0", l, r, top, b)
    end))
end

-- ---------------------------------------------------------------------
-- Money
-- ---------------------------------------------------------------------

local COPPER = { gold = 10000, silver = 100, copper = 1, g = 10000, s = 100, c = 1 }
local function count(d) return tonumber((d:gsub("%D", ""))) end

-- Each coin in a text as a mark holding its copper: the game's coins
-- (|A:coin-gold|a, MoneyFormatterUtil), the old coin textures
-- (UI-GoldIcon, GetCoinTextureString) and Daylight UI's own.
local function mark(d, kind)
    local n, k = count(d), COPPER[kind:lower()]
    if not (n and k) then return nil end
    return "\1" .. (n * k) .. "\2"
end
local function marked(t)
    t = t:gsub("(%d[%d,%.]*)%s?|A:coin%-(%a+):[^|]*|a", mark)
    t = t:gsub("(%d[%d,%.]*)%s?|T[^|]-UI%-(%a+)Icon[^|]*|t", mark)
    t = t:gsub("(%d[%d,%.]*)%s?|T[^|]-coin%-(%a+)[^|]*|t", mark)
    return t
end

-- Coins written as letters (TSM: 12g 34s 56c, the letters colored) only
-- count when that's all the text says: "5s" in a sentence is a time.
local function lettersOnly(t)
    local total, any = 0, false
    for d, k in t:gmatch("(%d[%d,%.]*)([gsc])") do
        total, any = total + (count(d) or 0) * COPPER[k], true
    end
    if not any then return nil end
    if t:gsub("%d[%d,%.]*[gsc]", ""):find("%S") then return nil end
    return total
end

-- The copper a text holds when the whole of it is money, else nil.
function Foreign.CopperOf(text)
    if type(text) ~= "string" then return nil end
    local t = trim(marked(strip(text)))
    local letters = lettersOnly(t)
    if letters then return letters end
    local total, any = 0, false
    local rest = t:gsub("\1(%d+)\2", function(c)
        total, any = total + tonumber(c), true
        return ""
    end)
    if any and not rest:find("%S") then return total end
    return nil
end

-- The text with every run of coins in it as Daylight UI's (W.Money); the text
-- as it was when it holds none.
function Foreign.Money(text)
    if type(text) ~= "string" then return text end
    local whole = Foreign.CopperOf(text)
    if whole then return DUI.Widgets.Money(whole) end
    local t = marked(strip(text))
    if not t:find("\1", 1, true) then return text end
    -- Coins side by side are one amount.
    local merged
    repeat
        t, merged = t:gsub("\1(%d+)\2(%s*)\1(%d+)\2", function(a, _, b) return "\1" .. (a + b) .. "\2" end)
    until merged == 0
    return (t:gsub("\1(%d+)\2", function(c) return DUI.Widgets.Money(tonumber(c)) end))
end

-- One side of a line in the card's words: icons cropped, coins Daylight UI's,
-- a typed-in gray tan.
function Foreign.Words(t)
    if type(t) ~= "string" then return t end
    t = Foreign.Crop(t)
    local money = Foreign.Money(t)
    if money ~= t then return money end
    return Foreign.UnGray(t)
end

-- The money frames the game hangs on a tooltip's lines (SetTooltipMoney: a
-- blank line, and <tooltip>MoneyFrame<n> anchored to its left text with the
-- amount and the words before and after it). Fills into[i] = { copper,
-- prefix, suffix } for each line from `from` on that has one.
function Foreign.MoneyFrames(tip, from, n, into)
    local shown = tip.shownMoneyFrames
    if isSecret(shown) or type(shown) ~= "number" or shown < 1 then return end
    local name = tip.GetName and tip:GetName()
    if type(name) ~= "string" then return end
    local Tip = ns.Tooltip
    for k = 1, shown do
        local mf = _G[name .. "MoneyFrame" .. k]
        local copper = type(mf) == "table" and mf.staticMoney
        if type(copper) == "number" and not isSecret(copper) and mf:IsShown() then
            local _, rel = mf:GetPoint(1)
            if not isSecret(rel) and rel ~= nil then
                for i = from, n do
                    if Tip.Line(tip, i) == rel then
                        local pre = type(mf.PrefixText) == "table" and mf.PrefixText:GetText() or nil
                        local post = type(mf.SuffixText) == "table" and mf.SuffixText:GetText() or nil
                        if isSecret(pre) then pre = nil end
                        if isSecret(post) then post = nil end
                        into[i] = { copper, pre, post }
                        break
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- The plain repaint
-- ---------------------------------------------------------------------

-- A side's color: the game's white and yellow become the card's (left soft
-- white, right white), red stays a warning, gray turns tan, any other color
-- (a class, a quality) stays its own.
local function sideColor(line, right)
    local INK = Style.INK
    local has = right and line.hasRC or (not right and line.hasLC)
    local c = has and (right and line.rc or line.lc) or nil
    if not c then return right and INK.VALUE or INK.TEXT end
    local kind = DUI.Tips.GameColor(c[1], c[2], c[3])
    if kind == "white" then return right and INK.VALUE or INK.TEXT end
    if kind == "yellow" then return INK.TEXT end
    if kind == "red" then return INK.BAD end
    if Foreign.Gray(c) then return INK.LABEL end
    return c
end
Foreign.SideColor = sideColor

-- A label for a row: no color codes, no colon at its end.
local function label(t)
    return (trim(strip(t or "")):gsub("%s*:$", ""))
end

local function moneyRow(p, line, money)
    local Panel, INK = ns.RichPanel, Style.INK
    local words = money[2]
    if Foreign.Blank(words) then words = not Foreign.Blank(line.left) and line.left or "" end
    local value = DUI.Widgets.Money(money[1])
    if not Foreign.Blank(money[3]) then value = value .. " " .. trim(strip(money[3])) end
    Panel.Row(p, label(words), value, INK.VALUE, INK.TEXT)
end

-- One line, repainted. money: the money frame on it, if any.
function Foreign.Line(p, line, money)
    local Panel = ns.RichPanel
    if money then return moneyRow(p, line, money) end
    if line.right and not Foreign.Blank(line.right) then
        Panel.Row(p, Foreign.Words(line.left or ""), Foreign.Words(line.right), sideColor(line, true), sideColor(line))
    elseif ns.Rich.IsFlavor(line) then
        ns.Rich.Flavor(p, line)
    else
        Panel.Text(p, Foreign.Words(line.left), sideColor(line))
    end
end

-- ---------------------------------------------------------------------
-- Adapters: one small table per addon's kind of line. match(lines, i, n,
-- money) returns the last line it takes from i (nil: not its line); draw(p,
-- lines, from, to, money) lays them out.
-- ---------------------------------------------------------------------

local function questKey(t)
    return (ns.Rich.Bare(t):gsub("^%[[^%]]*%]%s*", "")):lower()
end
Foreign.QuestKey = questKey

Foreign.ADAPTERS = {
    -- Questie's quest rows (any addon writing "Quest name", then "   3/10
    -- Thing [37%]" rows): a heading in the quest's difficulty color and an
    -- accent bar per objective, as the game's own quest lines.
    {
        key = "questie", quest = true,
        match = function(lines, i, n)
            local Rich = ns.Rich
            local kind = Rich.QuestLine(lines, i, n)
            if kind ~= "title" and kind ~= "objective" then return nil end
            local j = i
            while j < n do
                local next = Rich.QuestLine(lines, j + 1, n)
                if next ~= "objective" and next ~= "player" then break end
                j = j + 1
            end
            return j
        end,
        draw = function(p, lines, from, to) ns.Rich.Lines(p, to, lines, from) end,
    },
    -- Prices (Auctionator, TSM, a vendor price): a label and an amount of
    -- money, or "Label: amount" on one side, or the game's money frame. The
    -- label in the card's words, the amount as Daylight UI's coins.
    {
        key = "prices",
        match = function(lines, i, n, money)
            local line = lines[i]
            if money[i] then return i end
            if line.right and Foreign.CopperOf(line.right) and not Foreign.Blank(line.left) then return i end
            if not line.right and line.left then
                local head, tail = strip(line.left):match("^(.-):%s*(.+)$")
                if head and head:find("%S") and Foreign.CopperOf(tail) then return i end
            end
            return nil
        end,
        draw = function(p, lines, i, _, money)
            local Panel, INK = ns.RichPanel, Style.INK
            local line = lines[i]
            if money[i] then return moneyRow(p, line, money[i]) end
            local head, copper
            if line.right then
                head, copper = line.left, Foreign.CopperOf(line.right)
            else
                local h, tail = strip(line.left):match("^(.-):%s*(.+)$")
                head, copper = h, Foreign.CopperOf(tail)
            end
            Panel.Row(p, label(head), DUI.Widgets.Money(copper), INK.VALUE, INK.TEXT)
        end,
    },
    -- A score (Raider.IO's "M+ Score  2140"): the label, the number popped.
    {
        key = "score",
        match = function(lines, i)
            local line = lines[i]
            local left, right = line.left and strip(line.left) or nil, line.right and strip(line.right) or nil
            if not left then return nil end
            if not right then left, right = left:match("^(.-):%s*(.+)$") end
            if not (left and right) then return nil end
            local low = left:lower()
            if not (low:find("score", 1, true) or low:find("rating", 1, true)) then return nil end
            if not trim(right):match("^[%d,%.]+%+?$") then return nil end
            return i
        end,
        draw = function(p, lines, i)
            local line = lines[i]
            local left, right = strip(line.left), line.right and strip(line.right) or nil
            if not right then left, right = left:match("^(.-):%s*(.+)$") end
            local r, g, b = Style.Pop()
            ns.RichPanel.Row(p, label(left), trim(right), { r, g, b }, Style.INK.TEXT)
        end,
    },
}

-- ---------------------------------------------------------------------
-- Reading and placing
-- ---------------------------------------------------------------------

-- Read once per build (Rich.Build), before the card: what other addons
-- added from line `from` on, and the plugin pieces among them. The card
-- finds it in p.foreign. pieces: line -> a plugin's piece (Rich.Piece).
function Foreign.Read(p, tip, n, lines, own, pieces)
    local f = p.foreign or { money = {}, tags = {}, blocks = {}, shown = {} }
    p.foreign = f
    f.n, f.lines, f.from, f.pieces = n, lines, own + 1, pieces
    f.blocksFor, f.questsTaken = false, false
    for k in pairs(f.money) do f.money[k] = nil end
    for k = #f.tags, 1, -1 do f.tags[k] = nil end
    Foreign.MoneyFrames(tip, f.from, n, f.money)
    if pieces then
        for i = f.from, n do
            local piece = pieces[i]
            if piece and piece.kind == "tag" then
                -- Colored like every other tag: the addon's color, else the accent.
                f.tags[#f.tags + 1] = ns.RichItems.Tag(piece.text, piece.color or { Style.Pop() })
            end
        end
    end
    -- The quests the game's own lines already show: another addon's rows for
    -- one of them are left out.
    for k in pairs(f.shown) do f.shown[k] = nil end
    for i = 2, math.min(own, n) do
        if ns.Rich.QuestLine(lines, i, own) == "title" then f.shown[questKey(lines[i].left)] = true end
    end
    return f
end

local function block(f, kind, from, to, extra)
    local b = f.blocks[#f.blocks + 1] or {}
    f.blocks[#f.blocks + 1] = b
    b.kind, b.from, b.to, b.adapter, b.piece = kind, from, to, extra and extra.adapter, extra and extra.piece
    return b
end

-- The lines sorted into blocks, once per build. taken: lines the card drew
-- itself (an item's sell price, a compare's changes).
function Foreign.Blocks(f, taken)
    if f.blocksFor then return f.blocks end
    f.blocksFor = true
    for k = #f.blocks, 1, -1 do f.blocks[k] = nil end
    local lines, n, pieces, money = f.lines, f.n, f.pieces, f.money
    local i = f.from
    while i <= n do
        local line = lines[i]
        local piece = pieces and pieces[i]
        if taken and taken[i] then
            i = i + 1
        elseif piece then
            if piece.kind ~= "tag" then block(f, "piece", i, i, { piece = piece }) end
            i = i + 1
        elseif not money[i] and Foreign.Blank(line.left) and Foreign.Blank(line.right) then
            -- A gap, never two, never first.
            local last = f.blocks[#f.blocks]
            if last and last.kind ~= "gap" then block(f, "gap", i, i) end
            i = i + 1
        else
            local done = false
            for _, a in ipairs(Foreign.ADAPTERS) do
                if adapterOn(a.key) then
                    local j = a.match(lines, i, n, money)
                    if j then
                        -- A quest the game's own lines already show: not twice.
                        local kind = (a.quest and f.shown[questKey(line.left)]) and "drop" or "adapter"
                        block(f, kind, i, j, { adapter = a })
                        i, done = j + 1, true
                        break
                    end
                end
            end
            if not done then
                block(f, "line", i, i)
                i = i + 1
            end
        end
    end
    while f.blocks[#f.blocks] and f.blocks[#f.blocks].kind == "gap" do f.blocks[#f.blocks] = nil end
    return f.blocks
end

-- Whether a block goes at this spot: everything where the setting says; a
-- plugin's pieces (Daylight UI's own API) also when other addons are hidden;
-- a quest block not where the card has drawn it with its own quests.
local function wanted(f, b, spot)
    if b.kind == "drop" then return false end
    if b.adapter and b.adapter.quest and f.questsTaken then return false end
    local where = Foreign.Where()
    if where == spot then return true end
    return where == "hidden" and spot == "own" and b.kind == "piece"
end

function Foreign.Has(p, spot, taken)
    local f = p.foreign
    if not f then return false end
    for _, b in ipairs(Foreign.Blocks(f, taken)) do
        if b.kind ~= "gap" and wanted(f, b, spot) then return true end
    end
    return false
end

-- The quest rows another addon added (and the card shows with its own
-- quests): a set of the lines that are NOT one, for Rich.Lines' skip.
-- Returns it, and whether there's any.
function Foreign.QuestLines(p, taken)
    local f = p.foreign
    local notQuest, any = {}, false
    if not f then return notQuest, false end
    f.questsTaken = true
    for i = f.from, f.n do notQuest[i] = true end
    for _, b in ipairs(Foreign.Blocks(f, taken)) do
        if b.kind == "adapter" and b.adapter.quest then
            for i = b.from, b.to do notQuest[i] = nil end
            any = true
        end
    end
    return notQuest, any
end

-- Draws them at a card's spot: "mixed" (with its own rows, where the card
-- calls it) or "own" (their own area, at the bottom after a rule). Returns
-- whether anything was drawn.
function Foreign.Place(p, spot, taken)
    local f = p.foreign
    if not (f and Foreign.Has(p, spot, taken)) then return false end
    local Panel = ns.RichPanel
    if spot == "own" then
        local last = p.items[p.count]
        if p.count > 0 and last.kind ~= "rule" then Panel.Rule(p) end
    end
    local drew, gap, quest = false, false, false
    for _, b in ipairs(f.blocks) do
        if b.kind == "gap" then
            gap = drew
        elseif wanted(f, b, spot) then
            -- A quest block has a rule on each side, as the game's own quests.
            local isQuest = b.adapter ~= nil and b.adapter.quest == true
            if quest and not isQuest then
                Panel.Rule(p)
            elseif gap and not isQuest then
                Panel.Gap(p, Foreign.GAP)
            end
            gap, drew, quest = false, true, isQuest
            if b.kind == "piece" then
                Foreign.Piece(p, b.piece)
            elseif b.kind == "adapter" then
                b.adapter.draw(p, f.lines, b.from, b.to, f.money)
            else
                Foreign.Line(p, f.lines[b.from], f.money[b.from])
            end
        end
    end
    return drew
end

-- ---------------------------------------------------------------------
-- Plugins' pieces (API 1.12, Tip.PLUGIN_LINES)
-- ---------------------------------------------------------------------

local function rgbOf(c, fallback)
    if type(c) == "table" and type(c[1]) == "number" then return c end
    return fallback
end

function Foreign.Piece(p, piece)
    local Panel, INK, SIZE = ns.RichPanel, Style.INK, Style.SIZE
    local k = piece.kind
    if k == "row" then
        Panel.Row(p, piece.label, piece.value, rgbOf(piece.color, INK.VALUE), rgbOf(piece.labelColor, INK.TEXT))
    elseif k == "text" then
        Panel.Text(p, piece.text, rgbOf(piece.color, INK.TEXT))
    elseif k == "hint" then
        Panel.Text(p, piece.text, { Style.Accent() }, SIZE.small)
    elseif k == "gap" then
        Panel.Gap(p, Foreign.GAP)
    elseif k == "section" then
        Panel.Section(p, piece.text)
    elseif k == "bar" then
        local c = rgbOf(piece.color, nil)
        local r, g, b
        if c then r, g, b = c[1], c[2], c[3] else r, g, b = Style.Accent() end
        Panel.Row(p, piece.label, string.format(L["%s / %s"], piece.shown, piece.shownMax), { r, g, b }, INK.TEXT)
        local lo, hi = DUI.Gradients.PairFrom({ r, g, b })
        Panel.Bar(p, { value = piece.value, max = piece.max, pair = { lo, hi }, h = 4 })
    elseif k == "tiles" then
        Panel.Tiles(p, piece.tiles)
    end
end
