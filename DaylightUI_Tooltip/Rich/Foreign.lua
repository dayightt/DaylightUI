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
-- Where they go on a card is the card's "addons" piece (Rich/Layout.lua): by
-- default their own area at the bottom after a line, anywhere the player
-- drags it, or hidden.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local isSecret = DUI.IsSecret
local L = DUI.L

local Foreign = {}
ns.RichForeign = Foreign

Foreign.GAP = 4 -- a blank line between two of an addon's lines

local function cfg() return ns.Tooltip.Config() or {} end

-- Whether other addons' lines show on a card of this kind (Rich/Layout.lua's
-- kinds). A card with no layout of its own (a mailbox, a node, anything
-- else) shows them unless every card hides them.
function Foreign.Shown(kind)
    local Layout = ns.RichLayout
    if kind then return Layout.Shown(kind, "addons") end
    for _, k in ipairs(Layout.KINDS) do
        if Layout.Shown(k, "addons") then return true end
    end
    return false
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
-- Digits with one or two after a decimal mark are a time or a rate ("1.49s",
-- a pet's attack speed), never coins: a thousands mark has three after it.
local function count(d)
    if d:find("[%.,]%d%d?$") then return nil end
    return tonumber((d:gsub("%D", "")))
end

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
        local n = count(d)
        if not n then return nil end
        total, any = total + n * COPPER[k], true
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

-- A coin letter in its own color code right after its digits (TSM's
-- "1|cffc7c7cfs|r", the digits maybe colored too) is money even beside other
-- words, like "[+46%] 1s 01c". Plain "5s" in a sentence is still a time.
-- A color code's hex can end in digits (TSM's |cffecf4f3, |cffffd100), and the
-- coin patterns would read those as the start of the price and tear the code
-- apart. While looking for coins, a code's digits are swapped for bytes no
-- text uses, and put back after.
local HIDDEN = "|c" .. ("[%a\14-\23]"):rep(8)
local function hideCodes(t)
    return (t:gsub("|c(%x%x%x%x%x%x%x%x)", function(hex)
        return "|c" .. hex:gsub("%d", function(d) return string.char(14 + d) end)
    end))
end
local function showCodes(t)
    return (t:gsub("[\14-\23]", function(c) return string.char(c:byte() + 34) end))
end

local function coloredLetters(t)
    t = t:gsub("(%d[%d,%.]*)|r" .. HIDDEN .. "([gsc])|r", function(d, k)
        local m = mark(d, k)
        return m and ("|r" .. m) or nil
    end)
    return (t:gsub("(%d[%d,%.]*)" .. HIDDEN .. "([gsc])|r", mark))
end

-- The text with every run of coins in it as Daylight UI's (W.Money); the text
-- as it was when it holds none. The words around the coins keep their colors.
function Foreign.Money(text)
    if type(text) ~= "string" then return text end
    local whole = Foreign.CopperOf(text)
    if whole then return DUI.Widgets.Money(whole) end
    local t = marked(coloredLetters(hideCodes(text)))
    if not t:find("\1", 1, true) then return text end
    -- Coins side by side are one amount. A color that was left holding nothing
    -- (its digits became the coin) sits between them and draws nothing.
    t = t:gsub(HIDDEN .. "|r", "")
    local merged
    repeat
        t, merged = t:gsub("\1(%d+)\2(%s*)\1(%d+)\2", function(a, _, b) return "\1" .. (a + b) .. "\2" end)
    until merged == 0
    t = showCodes(t)
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

-- A row whose two sides don't fit the card side by side: its words wrap on a
-- line of their own and the right side goes under them, at the right edge.
-- Cut to fit, the left side lost its end ("-55.1..." beside a long "vs ...").
-- A card of a fixed width first widens as far as it may (Panel.GROW) to keep
-- the two on one line: a price under a long label ("Region Market Value Avg")
-- reads best beside it.
local function row(p, left, right, rightColor, leftColor)
    local Panel = ns.RichPanel
    Panel.Row(p, left, right, rightColor, leftColor)
    local item = p.items[p.count]
    if not (item and item.kind == "row" and item.value) then return end
    local lw, rw = item.label:GetStringWidth(), item.value:GetStringWidth()
    if type(lw) ~= "number" or type(rw) ~= "number" or isSecret(lw) or isSecret(rw) then return end
    local most = Panel.WIDTH[p.kind] or Panel.WIDTH.other
    if Panel.FIXED[p.kind] then most = math.floor(most * Panel.GROW) end
    local inner = most - 2 * (p.padX or Panel.PAD_X)
    local need = lw + Panel.ROW_GAP_X + rw
    if need <= inner then
        item.need = need
        return
    end
    -- Undo the row: its two texts were the last taken from the pool.
    item.label:Hide()
    item.value:Hide()
    p.used.text = p.used.text - 2
    p.items[p.count], p.count = nil, p.count - 1
    if not Foreign.Blank(left) then Panel.Text(p, left, leftColor) end
    -- A right side wider than the card on its own (a long list of zones)
    -- would run past the left edge at the right: it wraps like a sentence.
    if rw > inner then
        Panel.Text(p, right, rightColor)
    else
        Panel.Row(p, "", right, rightColor)
        p.items[p.count].need = rw
    end
end
Foreign.Row = row

-- One line, repainted. money: the money frame on it, if any.
function Foreign.Line(p, line, money)
    local Panel = ns.RichPanel
    if money then return moneyRow(p, line, money) end
    if line.right and not Foreign.Blank(line.right) then
        row(p, Foreign.Words(line.left or ""), Foreign.Words(line.right), sideColor(line, true), sideColor(line))
    elseif ns.Rich.IsFlavor(line) then
        ns.Rich.Flavor(p, line)
    else
        Panel.Text(p, Foreign.Words(line.left), sideColor(line))
    end
end

-- An addon's title over its own lines ("Forever Leveling BiS" with its logo):
-- words alone on the left, short, not a sentence or a "Label:", in a color of
-- their own or after an icon, opening a part (the area's first line or after
-- a blank one) with more lines under it. It becomes a heading like the card's
-- own parts, so each addon's lines read as a group of their own.
Foreign.HEAD_MAX = 40 -- letters; longer reads as a sentence

function Foreign.Heading(lines, i, n, money, opens)
    local line = lines[i]
    if not opens or money[i] or not line.left or not Foreign.Blank(line.right) then return false end
    local words = ns.Rich.Bare(line.left)
    if words == "" or #words > Foreign.HEAD_MAX or words:find("[:%.!?]$") then return false end
    local raw = trim(line.left)
    local colored = raw:find("^|T") ~= nil
    if not colored then
        local own = raw:match("^|c%x%x(%x%x%x%x%x%x)")
        if own then
            local r, g, b = own:sub(1, 2), own:sub(3, 4), own:sub(5, 6)
            colored = not grayHex(r, g, b) and own:lower() ~= "ffffff"
        elseif line.hasLC then
            local kind = DUI.Tips.GameColor(line.lc[1], line.lc[2], line.lc[3])
            colored = kind ~= "white" and not Foreign.Gray(line.lc)
        end
    end
    if not colored then return false end
    for j = i + 1, n do
        if money[j] or not (Foreign.Blank(lines[j].left) and Foreign.Blank(lines[j].right)) then return true end
    end
    return false
end

-- A hint ("Hold Ctrl for details", "Alt-click: guide me"): a short line on
-- its own naming a modifier key or a click. Small, its key in the accent, as
-- Daylight UI's own hints.
local function keyWords()
    local out = { "shift", "ctrl", "alt", "click" }
    for _, k in ipairs({ _G.SHIFT_KEY_TEXT, _G.CTRL_KEY_TEXT, _G.ALT_KEY_TEXT }) do
        if type(k) == "string" and k:find("^%a+$") then out[#out + 1] = k:lower() end
    end
    -- Whole words only: "Altar" isn't Alt.
    for i, k in ipairs(out) do out[i] = "%f[%w]" .. k .. "%f[^%w]" end
    return out
end

function Foreign.IsHint(line)
    if not line.left or not Foreign.Blank(line.right) then return false end
    local words = strip(line.left)
    if #words > Foreign.HEAD_MAX then return false end
    local low = words:lower()
    if low:find("%f[%w]click%f[^%w]") then return true end
    -- A key alone needs a sign it's pressed: "Alt-", "Shift+", "Ctrl:",
    -- "Hold Ctrl". Plain "alt" is also a second character ("known by your alt").
    for _, k in ipairs(keyWords()) do
        if low:find(k .. "%s*[%-%+:]") or low:find("^hold%s+" .. k) or low:find("^press%s+" .. k) then return true end
    end
    return false
end

function Foreign.Hint(p, line)
    local words = trim(strip(Foreign.Crop(line.left)))
    local hex = DUI.Win.Parts.Hex({ Style.Accent() })
    local key, what = words:match("^(.-:)(%s.*)$")
    if key then
        words = hex .. key .. "|r" .. what
    else
        -- The first key word ("Hold Ctrl for details": Ctrl) in the accent.
        local low, at, to = words:lower(), nil, nil
        for _, k in ipairs(keyWords()) do
            local s, e = low:find(k)
            if s and (not at or s < at) then at, to = s, e end
        end
        if at then
            -- The whole word it's in ("Alt-click", "Shift-right-click").
            while at > 1 and words:sub(at - 1, at - 1):find("[%w%-]") do at = at - 1 end
            while to < #words and words:sub(to + 1, to + 1):find("[%w%-]") do to = to + 1 end
            words = words:sub(1, at - 1) .. hex .. words:sub(at, to) .. "|r" .. words:sub(to + 1)
        end
    end
    ns.RichPanel.Text(p, words, Style.INK.TEXT, Style.SIZE.small)
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
    -- ItemTree's block: its verdict tag as a picture with "ItemTree" on the
    -- right, then its status, reasons and uses, ending in its key hint. A
    -- section of its own, the verdict read from its API (ItemTreeAPI) as
    -- colored tags, its status a tag too; without the API its picture stays.
    {
        key = "itemtree",
        match = function(lines, i, n)
            if not Foreign.ItemTreeLine(lines[i]) then return nil end
            for j = i + 1, n do
                if Foreign.ItemTreeHint(lines[j]) then return j end
            end
            return n
        end,
        draw = function(p, lines, from, to, money) Foreign.ItemTree(p, lines, from, to, money) end,
    },
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
        -- The label keeps the addon's own colors and indent (TSM's disenchant
        -- results under their heading, each in its quality color) and wraps
        -- when it's long, as any other line of theirs.
        draw = function(p, lines, i, _, money)
            local INK = Style.INK
            local line = lines[i]
            if money[i] then return moneyRow(p, line, money[i]) end
            local head, copper
            if line.right then
                head, copper = line.left, Foreign.CopperOf(line.right)
            else
                local h, tail = line.left:match("^(.-):%s*(.+)$")
                head, copper = h, Foreign.CopperOf(tail)
            end
            head = Foreign.Words(head or ""):gsub(":(|r)%s*$", "%1"):gsub(":%s*$", "")
            row(p, head, DUI.Widgets.Money(copper), INK.VALUE, sideColor(line))
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
-- ItemTree
-- ---------------------------------------------------------------------


-- One of ItemTree's own lines: its art at the start (the verdict tag, a status
-- badge), or its name alone on the right.
function Foreign.ItemTreeLine(line)
    if type(line) ~= "table" or type(line.left) ~= "string" then return false end
    if line.left:find("^%s*|T[^|]*ItemTree") then return true end
    return type(line.right) == "string" and trim(strip(line.right)) == "ItemTree"
end

-- Its closing hint, "Ctrl + right click or ALT-I for the full tree" (the key
-- comes from the player's own bindings, so only the end is fixed).
function Foreign.ItemTreeHint(line)
    return type(line) == "table" and type(line.left) == "string" and Foreign.Blank(line.right)
        and strip(line.left):find("full tree%s*$") ~= nil
end

-- Its verdict words, by the tags its API gives, each in the color of what to do.
Foreign.ITEMTREE_TAGS = {
    keep = { L["Keep"], "GOOD" },
    vendor = { L["Vendor"], "MONEY" },
    auction = { L["Auction"], "MONEY" },
    disenchant = { L["Disenchant"], "pop" },
    worthless = { L["Worthless"], "OFF" },
}
Foreign.ITEMTREE_ACTIONS = { open = L["Open it"], use = L["Use it"], quest = L["Start its quest"] }

local function inkOf(key)
    if key == "pop" then return { Style.Pop() } end
    return Style.INK[key]
end

-- The tags for an item from ItemTree's API, or nil when there's no answer.
function Foreign.ItemTreeTags(id)
    local api = rawget(_G, "ItemTreeAPI")
    if type(id) ~= "number" or isSecret(id) or type(api) ~= "table" or api.version ~= 1
        or type(api.GetItemFacts) ~= "function" then return nil end
    -- Its API catches its own errors and answers nil instead.
    local facts = api.GetItemFacts(id)
    local k = type(facts) == "table" and facts.keep or nil
    if type(k) ~= "table" then return nil end
    local out = {}
    local a = k.action
    if type(a) == "table" and a.now == true and Foreign.ITEMTREE_ACTIONS[a.kind] then
        out[#out + 1] = ns.RichItems.Tag(Foreign.ITEMTREE_ACTIONS[a.kind], { Style.Pop() })
    end
    for _, tag in ipairs(type(k.tags) == "table" and k.tags or {}) do
        local t = Foreign.ITEMTREE_TAGS[tag]
        if t then out[#out + 1] = ns.RichItems.Tag(t[1], inkOf(t[2])) end
    end
    return out
end

-- A status line ("Changed in Forever" after its badge): its words alone.
local function statusWords(line)
    if Foreign.Blank(line.right) and line.left:find("^%s*|T[^|]*ItemTree[^|]*|t") then
        local words = trim(strip(line.left:gsub("|T[^|]*|t", "")))
        if words ~= "" then return words end
    end
    return nil
end

function Foreign.ItemTree(p, lines, from, to, money)
    local Panel = ns.RichPanel
    Panel.Section(p, "ItemTree")
    local f = p.foreign
    local tags = Foreign.ItemTreeTags(f and f.itemID)
    local i = from
    -- Its verdict picture: the API's tags in its place.
    if tags and Foreign.ItemTreeLine(lines[i]) and trim(strip(lines[i].right or "")) == "ItemTree" then i = i + 1 end
    -- The blank lines and status right under it join the tags.
    while tags and i <= to do
        local line = lines[i]
        if Foreign.Blank(line.left) and Foreign.Blank(line.right) and not money[i] then
            i = i + 1
        else
            local words = statusWords(line)
            if not words then break end
            tags[#tags + 1] = ns.RichItems.Tag(words, { Style.Pop() })
            i = i + 1
        end
    end
    if tags and #tags > 0 then Panel.Tags(p, tags) end
    local gap = false
    for k = i, to do
        local line = lines[k]
        if not money[k] and Foreign.Blank(line.left) and Foreign.Blank(line.right) then
            gap = true
        else
            if gap then Panel.Gap(p, Foreign.GAP) end
            gap = false
            if k == to and Foreign.ItemTreeHint(line) then
                Foreign.Hint(p, line)
            elseif trim(strip(line.right or "")) == "ItemTree" then
                -- Its picture with no API to read: the picture alone.
                Panel.Text(p, Foreign.Words(line.left), sideColor(line))
            else
                Foreign.Line(p, line, money[k])
            end
        end
    end
end

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
    -- Questie's rows for one of those quests are left out as a repeat, but
    -- their drop chances aren't in the game's lines: keep them, by quest and
    -- objective, for the game's rows to show (Foreign.Chance).
    f.chances = f.chances or {}
    for k in pairs(f.chances) do f.chances[k] = nil end
    local quest
    for i = f.from, n do
        local kind = ns.Rich.QuestLine(lines, i, n)
        if kind == "title" then
            quest = f.shown[questKey(lines[i].left)] and questKey(lines[i].left) or nil
        elseif kind == "objective" then
            local name, _, _, chance = ns.Rich.Objective(lines[i])
            if quest and chance then
                f.chances[quest] = f.chances[quest] or {}
                f.chances[quest][name:lower()] = chance
            end
        elseif kind ~= "player" then
            quest = nil
        end
    end
    return f
end

-- Another addon's drop chance for an objective of a quest the game's own
-- lines show. quest: the title's QuestKey.
function Foreign.Chance(p, quest, name)
    local f = p.foreign
    local list = f and f.chances and quest and f.chances[quest]
    return list and name and list[name:lower()] or nil
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
            -- A gap, never two, never first, never right under a heading.
            local last = f.blocks[#f.blocks]
            if last and last.kind ~= "gap" and last.kind ~= "heading" then block(f, "gap", i, i) end
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
                local last = f.blocks[#f.blocks]
                local opens = not last or last.kind == "gap"
                local kind = "line"
                if Foreign.Heading(lines, i, n, money, opens) then
                    kind = "heading"
                elseif Foreign.IsHint(line) then
                    kind = "hint"
                end
                block(f, kind, i, i)
                i = i + 1
            end
        end
    end
    while f.blocks[#f.blocks] and f.blocks[#f.blocks].kind == "gap" do f.blocks[#f.blocks] = nil end
    return f.blocks
end

-- Whether a block is drawn: every one when other addons' lines show; else
-- only a plugin's pieces (Daylight UI's own API); never a quest block the card
-- draws with its own quests.
local function wanted(f, b, all)
    if b.kind == "drop" then return false end
    if b.adapter and b.adapter.quest and f.questsTaken then return false end
    return all or b.kind == "piece"
end

-- Whether there's anything to draw. all: other addons' lines show.
function Foreign.Has(p, all, taken)
    local f = p.foreign
    if not f then return false end
    for _, b in ipairs(Foreign.Blocks(f, taken)) do
        if b.kind ~= "gap" and wanted(f, b, all) then return true end
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

-- Draws them where the card puts them. all: other addons' lines show (else
-- only a plugin's pieces). Returns whether anything was drawn.
function Foreign.Place(p, all, taken)
    local f = p.foreign
    if not (f and Foreign.Has(p, all, taken)) then return false end
    local Panel = ns.RichPanel
    local drew, gap, quest = false, false, false
    for _, b in ipairs(f.blocks) do
        if b.kind == "gap" then
            gap = drew
        elseif wanted(f, b, all) then
            -- A quest block has a rule on each side, as the game's own quests.
            local isQuest = b.adapter ~= nil and b.adapter.quest == true
            if quest and not isQuest then
                Panel.Rule(p)
            elseif b.kind == "heading" and drew then
                -- Another addon's part starts: a rule, as between the card's parts.
                Panel.Rule(p)
            elseif gap and not isQuest then
                Panel.Gap(p, Foreign.GAP)
            end
            gap, drew, quest = false, true, isQuest
            if b.kind == "heading" then
                Panel.Section(p, ns.Rich.Bare(f.lines[b.from].left))
            elseif b.kind == "hint" then
                Foreign.Hint(p, f.lines[b.from])
            elseif b.kind == "piece" then
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

-- A card's "addons" piece for Rich/Layout.lua. Hidden, it still draws a
-- Daylight UI plugin's pieces (and the ID line) where the piece sits, so it
-- decides that itself (keep).
function Foreign.Part(p, kind, taken)
    local all = Foreign.Shown(kind)
    return { keep = true, has = Foreign.Has(p, all, taken), draw = function() Foreign.Place(p, all, taken) end }
end

-- Other addons' lines at the bottom of a card with no layout of its own,
-- after a rule.
function Foreign.Bottom(p)
    local all = Foreign.Shown()
    if not Foreign.Has(p, all) then return false end
    local last = p.items[p.count]
    if p.count > 0 and last.kind ~= "rule" then ns.RichPanel.Rule(p) end
    return Foreign.Place(p, all)
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
