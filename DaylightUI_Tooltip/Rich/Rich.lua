-- The Rich / Simple switch and what fills the rich card. Simple is the skinned
-- game tooltip, untouched. Rich lays its own card (Rich/Panel.lua) over the main
-- tooltip after every fill: the data post-calls mark it, and it's built on show
-- and from the tooltip's update, before anything is drawn, so lines other
-- addons add after ours are in it.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local isSecret = DUI.IsSecret
local L = DUI.L

local Rich = {}
ns.Rich = Rich

local Panel, Read = ns.RichPanel, ns.RichRead

-- The tooltips that get the card: the main one and the compare tooltips
-- beside it, and a clicked item's popup with its own compares.
Rich.TIPS = { GameTooltip = true, ItemRefTooltip = true, ShoppingTooltip1 = true, ShoppingTooltip2 = true,
              ItemRefShoppingTooltip1 = true, ItemRefShoppingTooltip2 = true }

-- The game's health bar hangs under the main tooltip only.
local function showBar(tip, on)
    if tip == GameTooltip then ns.Tooltip.ShowBar(on) end
end

local state = setmetatable({}, { __mode = "k" }) -- tooltip -> { data, dirty }

function Rich.On(tip)
    local cfg = ns.Tooltip.Config()
    if not (cfg and cfg.style == "rich" and type(tip) == "table") then return false end
    local name = tip.GetName and tip:GetName()
    return Rich.TIPS[name] == true
end

local function stateOf(tip)
    local s = state[tip]
    if not s then
        s = {}
        state[tip] = s
    end
    return s
end

-- From the data post-calls: the card is built on show, or before the next
-- draw when the tooltip is already up (a refill), after every other post-call.
function Rich.Filled(tip, data)
    if not Rich.On(tip) then return end
    Rich.Hook(tip)
    local s = stateOf(tip)
    s.data, s.dirty, s.refill = data, true, true
end

-- Emptied for new content: rebuilt from whatever comes next, data or not (an
-- addon's own AddLine tooltip has no data).
function Rich.Cleared(tip)
    local s = state[tip]
    if s then
        s.data, s.dirty = nil, true
        if s.pieces then
            for k in pairs(s.pieces) do s.pieces[k] = nil end
        end
    end
end

-- A Daylight UI plugin's piece (API 1.12: lines.Row, Bar, Tag...) for the
-- line just added for it: the card draws the piece, the frame-only look in a
-- fight keeps the plain line.
function Rich.Piece(tip, piece)
    if not Rich.On(tip) then return end
    local n = tip.NumLines and tip:NumLines()
    if isSecret(n) or type(n) ~= "number" or n < 1 then return end
    local s = stateOf(tip)
    s.pieces = s.pieces or {}
    s.pieces[n] = piece
end

-- The frame only, around the game's own lines (a secret line): its lines come
-- back, a spell's painted the way the skinned look paints them.
local NO_LINES = {}

local function frameOnly(tip, s, p)
    Panel.Unmute(p)
    Panel.Chrome(p)
    showBar(tip, true)
    if s.kind == "spell" then ns.Tooltip.PaintSpell(tip, s.data) end
end

-- Shown: built now if a fill is waiting, then fitted.
-- Post-hooks on the tooltip's own Show, SetShown and SetAlpha, put on once
-- Rich is first in use (a tooltip in the Simple look never gets them). The
-- client's Show puts a refilled tooltip back at full opacity and its size,
-- and waiting for the next update let one frame of the game's own tooltip
-- draw; the client's own fade sets the alpha of a muted one back up. So: a
-- fill waiting is built at the Show, and a muted tooltip goes back to alpha 0
-- the moment anything sets it. PrettyTooltip hooks the same methods on this
-- client.
local hooked = setmetatable({}, { __mode = "k" })
local holding = false
-- Another addon adds its lines after the fill (often after the game's own
-- Show) and then calls Show to fit them. The card takes them in at that Show:
-- the loot window fills its tooltip again every frame after the tooltip's own
-- update, so waiting for the next update left those lines drawn over the card.
local function caughtUp(tip, s)
    local p = Panel.Get(tip)
    if s.pill or not (p and p:IsShown()) or p.chrome then return end
    local n = tip.NumLines and tip:NumLines()
    if isSecret(n) then return end
    if n ~= s.lines then return Rich.Build(tip) end
    Panel.Mute(p)
end
local function nativeShown(tip)
    if not Rich.On(tip) then return end
    local s = state[tip]
    if s and tip:IsShown() then
        if s.dirty then DUI.SafeCall(Rich.Build, tip) else DUI.SafeCall(caughtUp, tip, s) end
    end
    if ns.Tooltip.Muted(tip) and not holding then
        holding = true
        tip:SetAlpha(0)
        holding = false
    end
end
function Rich.Hook(tip)
    if hooked[tip] or type(tip) ~= "table" or type(tip.Show) ~= "function" then return end
    hooked[tip] = true
    hooksecurefunc(tip, "Show", nativeShown)
    hooksecurefunc(tip, "SetShown", function(self, on)
        if not isSecret(on) and on then nativeShown(self) end
    end)
    hooksecurefunc(tip, "SetAlpha", function(self, a)
        if holding or not ns.Tooltip.Muted(self) then return end
        if not isSecret(a) and a == 0 then return end
        holding = true
        self:SetAlpha(0)
        holding = false
    end)
end

function Rich.Shown(tip)
    if not Rich.On(tip) then return Rich.Off(tip) end
    Rich.Hook(tip)
    local s = state[tip]
    -- Hidden and shown in one frame (an owner's refill): the same kind of card
    -- comes back, so the tooltip keeps the size it had (Panel.KeepSize).
    if s and s.hiddenAt == GetTime() and s.kind ~= "unit" and Rich.Kind(s.data) == s.kind then
        Panel.KeepSize(Panel.Get(tip))
    end
    if s and s.dirty then Rich.Build(tip) end
    local p = Panel.Get(tip)
    if p and p:IsShown() then Panel.Fit(p) end
end

-- Once a frame while shown (Tip.OnUpdate). Rebuilds when lines came or went
-- since the last build (another addon's AddLine) or the fight pill comes or
-- goes (a fight, Shift), or a spell's math (Shift) or cooldown, fits the game's
-- tooltip, and keeps a unit's bars and a cooldown's countdown live.
Rich.BAR_EVERY = 0.1
function Rich.Step(tip)
    local s = state[tip]
    if not s then return end
    if s.dirty then return Rich.Build(tip) end
    local Pill = ns.RichPill
    if s.unit or s.world then
        local want = (s.unit and Pill.Wanted(tip, s.unit)) or (s.world and Pill.WantedWorld(tip)) or false
        if (s.pill == true) ~= want then return Rich.Build(tip) end
    end
    if s.pill then
        -- A line another addon adds under the pill is muted too.
        local n = tip.NumLines and tip:NumLines()
        if not isSecret(n) and n ~= s.lines then
            s.lines = n
            local p = Panel.Get(tip)
            if p then Panel.Mute(p) end
        end
        Panel.MuteNew(Panel.Get(tip))
        return Pill.Step(tip, s.unit)
    end
    local p = Panel.Get(tip)
    -- Showing with no card and no pill (nothing marked it for a build): one now.
    if not (p and p:IsShown()) then return Rich.Build(tip) end
    local n = tip.NumLines and tip:NumLines()
    if not isSecret(n) and n ~= s.lines then return Rich.Build(tip) end
    if not p.chrome then
        Panel.MuteNew(p)
        Panel.KeepTags(p)
    end
    local sp = s.spell
    if sp and not p.chrome then
        if sp.ends and ns.RichSpells.Tick(p, sp) then return Rich.Build(tip) end
    end
    if not Panel.Fit(p) and not s.fromUnit then
        -- The size went secret since the build: the frame only.
        frameOnly(tip, s, p)
    end
    if s.unit and not p.chrome then
        local now = GetTime()
        if now >= (s.nextBars or 0) then
            s.nextBars = now + Rich.BAR_EVERY
            Panel.UpdateBars(p)
        end
    end
end

local function endPill(tip, s)
    if not (s and s.pill) then return end
    s.pill = false
    ns.RichPill.Hide()
    if ns.Tooltip.Muted(tip) == "pill" then ns.Tooltip.Unmute(tip) end
end

function Rich.Hidden(tip)
    local s = state[tip]
    endPill(tip, s)
    -- The data stays until the tooltip is cleared: an owner may fill it, hide
    -- it and show it again at once, and that show must build the card.
    -- A build already asked for (the game may clear a tooltip before hiding
    -- it) stays asked for.
    if s then
        s.dirty = s.dirty or s.data ~= nil
        s.lines, s.unit, s.world, s.swept, s.key, s.spell = nil, nil, nil, nil, nil, nil
        s.hiddenAt = GetTime()
    end
    Panel.Release(Panel.Get(tip))
    ns.Tooltip.ShowShell(tip, true)
    showBar(tip, true)
end

-- A setting changed: built again before the next draw, or put away.
function Rich.Refresh(tip)
    if Rich.On(tip) then
        local s = stateOf(tip)
        s.dirty = true
        -- The same lines no longer mean the same card (a piece moved or hid).
        if s.seen then s.seen.n = nil end
    else
        Rich.Off(tip)
    end
end

-- Rich switched off, or a tooltip it doesn't cover: the skinned look back.
function Rich.Off(tip)
    local p = Panel.Get(tip)
    if not (p or state[tip]) then return end
    endPill(tip, state[tip])
    if p and p:IsShown() then Panel.Release(p) end
    state[tip] = nil
    ns.Tooltip.ShowShell(tip, true)
    showBar(tip, true)
end

-- What the card's top light is: an item's quality, a unit's class or
-- reaction pair, else the accent.
function Rich.Light(tip, data, kind)
    local Tip = ns.Tooltip
    if kind == "item" then
        local q = Tip.Quality(Tip.ItemLink(tip, data))
        local r, g, b
        if q and q >= Tip.MIN_QUALITY then r, g, b = Tip.QualityColor(q) end
        if r then return { ns.RichItems.Lift({ r, g, b }), { r, g, b } }, true end
    elseif kind == "unit" then
        local unit = Read.Unit(tip)
        if unit and DUI.Gradients then
            local lo, hi = DUI.Gradients.PaintRGB(DUI.Gradients.KeyFor(unit))
            if type(lo) == "table" and type(hi) == "table" then return { hi, lo } end
        end
    end
    local lo, hi = Style.AccentPair()
    if lo then return { lo, hi } end
    local r, g, b = Style.Accent()
    local a, z = DUI.Gradients.PairFrom({ r, g, b })
    return { z, a }
end

-- Which card a data type gets (its widest size and light).
local KINDS
function Rich.Kind(data)
    local t = type(data) == "table" and data.type or nil
    if isSecret(t) then return "other" end
    local E = Enum and Enum.TooltipDataType
    if not KINDS and E then
        KINDS = {}
        if E.Unit then KINDS[E.Unit] = "unit" end
        if E.Item then KINDS[E.Item] = "item" end
        for _, k in ipairs({ "Spell", "UnitAura", "Macro" }) do
            if E[k] then KINDS[E[k]] = "spell" end
        end
    end
    return KINDS and KINDS[t] or "other"
end

local function rgb(c) return { c[1], c[2], c[3] } end

-- A row's value keeps its words as they are: white reads as a value, the
-- game's yellow as a sentence, red as bad, any other color its own.
local function valueColor(line)
    if not line.hasRC then return Style.INK.VALUE end
    local c = line.rc
    local kind = DUI.Tips.GameColor(c[1], c[2], c[3])
    if kind == "white" then return Style.INK.VALUE end
    if kind == "yellow" then return Style.INK.TEXT end
    if kind == "red" then return Style.INK.BAD end
    return rgb(c)
end

-- ---------------------------------------------------------------------
-- Quest lines: the game's own (typed QuestTitle and QuestObjective in the
-- data) and Questie's (text only: a count like 6/10, its drop chance [37%]).
-- A quest's name is a small heading in its difficulty color, each objective
-- a row with its count in the accent over a thin bar; a finished one dims,
-- with "Complete".
-- ---------------------------------------------------------------------

local LT = Enum and Enum.TooltipDataLineType
Rich.QUEST_TITLE = LT and LT.QuestTitle or 17
Rich.QUEST_OBJECTIVE = LT and LT.QuestObjective or 8
Rich.QUEST_PLAYER = LT and LT.QuestPlayer or 18
Rich.FLAVOR = LT and LT.FlavorText or 37

-- A thing's flavor text: the game's quote line ("Miners need a mining pick
-- for digging."), by its line type, or a line in quotation marks.
function Rich.IsFlavor(line)
    if not (line and line.left) or line.right then return false end
    if line.type == Rich.FLAVOR then return true end
    local t = Rich.Bare(line.left)
    return #t > 2 and t:sub(1, 1) == '"' and t:sub(-1) == '"'
end

-- The quote in the accent, small: it reads as a quote, not as one more fact.
function Rich.Flavor(p, line)
    local r, g, b = Style.Accent()
    Panel.Text(p, Rich.Bare(line.left), { r, g, b }, Style.SIZE.small)
end

-- The game names whose progress a quest's lines are under its title, for a
-- group. Your own name says nothing; a party member's does.
function Rich.OwnName(line)
    if not (line and line.left and line.type == Rich.QUEST_PLAYER) then return false end
    local me = UnitName("player")
    if isSecret(me) or type(me) ~= "string" then return false end
    return Rich.Bare(line.left) == me
end

local function plainString(v) return not isSecret(v) and type(v) == "string" and v ~= "" end

-- "player", then each party or raid unit, written into one reused list.
local units = {}
local function groupUnits()
    local raid = IsInRaid and IsInRaid() == true
    local n = raid and GetNumGroupMembers and GetNumGroupMembers() or 4
    if isSecret(n) or type(n) ~= "number" then n = 0 end
    for k in pairs(units) do units[k] = nil end
    units[1] = "player"
    for i = 1, n do units[#units + 1] = (raid and "raid" or "party") .. i end
    return units
end

-- The class of the group member a QuestPlayer line names ("Name" or "First
-- Last"), for coloring the name. Nil for anyone not in the group or when a
-- name can't be read.
function Rich.QuestPlayerClass(text)
    if not plainString(text) then return nil end
    local name = Rich.Bare(text)
    for _, unit in ipairs(groupUnits()) do
        local here = UnitExists(unit)
        if not isSecret(here) and here then
            local first, last = UnitFullName(unit)
            if isSecret(first) then first = nil end
            if isSecret(last) then last = nil end
            local match = type(first) == "string"
                and (first == name or (type(last) == "string" and first .. " " .. last == name))
            if match then
                local _, token = UnitClass(unit)
                if plainString(token) then return token end
                return nil
            end
        end
    end
    return nil
end

-- A QuestPlayer line's color: the member's class, else the label tan.
function Rich.QuestPlayerInk(text)
    local token = Rich.QuestPlayerClass(text)
    if token then return { Style.ClassTextColor(token) } end
    return Style.INK.LABEL
end

-- A line's words alone: no color codes, icons, leading spaces or dash.
function Rich.Bare(t)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return (t:gsub("^%s+", ""):gsub("^%-%s*", ""):gsub("%s+$", ""))
end

-- An objective line: its name, have, need (nil when it shows no count),
-- drop chance, done. nil when the line isn't one.
function Rich.Objective(line)
    if not line or line.right or not line.left then return nil end
    local t = Rich.Bare(line.left)
    local chance = t:match("%[([%d%.]+%%)%]")
    t = t:gsub("%s*%[[%d%.]+%%%]", "")
    local have, need, name = t:match("^(%d+)%s*/%s*(%d+)%s+(.+)$")
    if not have then name, have, need = t:match("^(.-):%s*(%d+)%s*/%s*(%d+)$") end
    if not have then
        if line.type == Rich.QUEST_OBJECTIVE then return t, nil, nil, chance, false end
        return nil
    end
    have, need = tonumber(have), tonumber(need)
    return name, have, need, chance, need > 0 and have >= need
end

-- A quest's difficulty color: from its id when the data has one, else found
-- by its name in your quest log (Questie's titles may lead with "[44]").
local logTitles = {}
function Rich.QuestColor(id, title)
    local Data = DUI.Npc and DUI.Npc.Data
    if not (Data and Data.QuestColor) then return nil end
    local level
    if not id and C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local want = Rich.Bare(title):gsub("^%[[^%]]*%]%s*", "")
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            local t = type(info) == "table" and not info.isHeader and info.title
            if type(t) == "string" and not isSecret(t) and t == want then
                id, level = info.questID, info.level
                break
            end
        end
    end
    if not id then return nil end
    return Data.QuestColor(id, level)
end

local function accentPair()
    local lo, hi = Style.AccentPair()
    if lo then return { lo, hi } end
    local r, g, b = Style.Accent()
    local a, z = DUI.Gradients.PairFrom({ r, g, b })
    return { a, z }
end

local function questRow(p, name, have, need, chance, done)
    local Hex = DUI.Win.Parts.Hex
    local label = name
    if chance and not done then label = name .. " " .. Hex(Style.INK.LABEL) .. chance .. "|r" end
    if done then
        Panel.Row(p, label, L["Complete"], Style.INK.GOOD, Style.INK.OFF, nil, nil, true)
    elseif have then
        local r, g, b = Style.Accent()
        Panel.Row(p, label, string.format(L["%d / %d"], have, need), { r, g, b }, Style.INK.TEXT, nil, nil, true)
        local cfg = ns.Tooltip.Config()
        if not (cfg and cfg.questBars == false) then
            Panel.Bar(p, { value = have, max = need, pair = accentPair(), h = 4 })
        end
    else
        Panel.Text(p, name, Style.INK.TEXT)
    end
end

-- An empty line: no text on either side (the game's AddLine(" ")).
local function isBlank(line)
    return line ~= nil and not line.right and ns.RichForeign.Blank(line.left)
end

-- Whether an objective is the next line after i, not counting empty ones: a gap
-- between a quest's heading and its objectives doesn't part them.
local function objectiveBelow(lines, i, n)
    local j = i + 1
    while j <= n and isBlank(lines[j]) do j = j + 1 end
    return j <= n and Rich.Objective(lines[j]) ~= nil
end

-- Whether line i is part of a quest: "title", "objective", "player" (whose
-- progress it is, in a group) or nil. n: the last line that counts.
function Rich.QuestLine(lines, i, n)
    local line = lines[i]
    if not line then return nil end
    if line.type == Rich.QUEST_PLAYER then return "player" end
    if Rich.Objective(line) ~= nil then return "objective" end
    if line.left and not line.right and not isBlank(line)
        and (line.type == Rich.QUEST_TITLE or objectiveBelow(lines, i, n)) then
        return "title"
    end
    return nil
end

-- A line with Daylight UI's coins in it (a price, a quest's reward).
local function hasCoin(line)
    return line and not line.right and type(line.left) == "string" and not isSecret(line.left)
        and line.left:find("|T[^|]-coin%-%a+") ~= nil
end

-- The tooltip's lines from line `from` on, in the card's look: a quest as
-- above, a line with two sides as a row, any other as a sentence, an empty
-- one as a gap. The colors go through the same rules as the skinned look
-- (Tips.GameSide). A quest block gets a rule before and after it. skip: lines
-- to pass over (a card that draws them its own way). ruled: the card already
-- put a line above (a section of its layout), so the first quest gets none.
function Rich.Lines(p, n, lines, from, skip, ruled)
    local Tips = DUI.Tips
    local inQuest, quest = ruled == true, nil
    local afterTitle = false -- the line before was a quest's heading
    for i = from, n do
        local line = lines[i]
        local gapOK = afterTitle
        afterTitle = false
        local kind = not (skip and skip[i]) and Rich.QuestLine(lines, i, n) or nil
        local who, title = kind == "player", kind == "title"
        local name, have, need, chance, done
        if kind == "objective" then
            name, have, need, chance, done = Rich.Objective(line)
            if not chance then chance = ns.RichForeign.Chance(p, quest, name) end
        end
        if title then quest = ns.RichForeign.QuestKey(line.left) end
        if skip and skip[i] then
            -- Drawn elsewhere.
        elseif gapOK and isBlank(line) and objectiveBelow(lines, i, n) then
            -- The gap between a quest's heading and its objectives: not a section break.
            afterTitle = true
        elseif who then
            -- Under a quest's title: a party member's name, small; yours, nothing.
            if not Rich.OwnName(line) then Panel.Text(p, Rich.Bare(line.left), Rich.QuestPlayerInk(line.left), Style.SIZE.small) end
        elseif title or name then
            if not inQuest and p.count > 0 and p.items[p.count].kind ~= "rule" then Panel.Rule(p) end
            inQuest = true
            if title then
                afterTitle = true
                Panel.Section(p, Rich.Bare(line.left), Rich.QuestColor(line.id, line.left))
            else
                questRow(p, name, have, need, chance, done)
            end
        else
            if inQuest then
                Panel.Rule(p)
                inQuest = false
            end
            if not line.left and not line.right then
                Panel.Gap(p, 4)
            elseif line.right then
                -- A long left side wraps rather than being cut: the game's tooltip
                -- can't wrap it, so this is where a long objective gets its room.
                Panel.Row(p, line.left or "", line.right, valueColor(line), nil, nil, nil, true)
            elseif Rich.IsFlavor(line) then
                Rich.Flavor(p, line)
            elseif hasCoin(line) then
                -- Money keeps its own color: read as a yellow description its numbers turned green.
                Panel.Text(p, line.left, line.hasLC and rgb(line.lc) or Style.INK.MONEY)
            else
                local t, c = Tips.GameSide(line.left, line.hasLC and line.lc or nil)
                Panel.Text(p, t, c)
            end
        end
    end
end

-- Any tooltip without a card of its own: the first line as the title, its
-- own lines as Rich.Lines, then other addons' (Rich/Foreign.lua).
function Rich.Generic(p, n, lines)
    local Foreign = ns.RichForeign
    local own = p.foreign and p.foreign.from - 1 or n
    local first = lines[1]
    if n >= 1 and first.left then
        local color = first.hasLC and rgb(first.lc) or nil
        -- The game's white or yellow heading reads as the card's white title;
        -- a color of its own (quality, class) stays.
        local kind = color and DUI.Tips.GameColor(color[1], color[2], color[3])
        if kind == "white" or kind == "yellow" then color = nil end
        -- A first line holding several (the mail icon's "Unread mail from:"
        -- with each sender under it): the first is the title, the rest lines.
        local title, rest = first.left:match("^([^\n]*)\n(.*)$")
        Panel.Header(p, { title = title or first.left, titleColor = color,
            right = first.right, rightColor = first.hasRC and rgb(first.rc) or nil })
        if rest then
            for part in rest:gmatch("[^\n]+") do Panel.Text(p, DUI.Tips.GameSide(part, first.hasLC and first.lc or nil)) end
        end
    end
    Rich.Lines(p, own, lines, 2)
    Foreign.Bottom(p)
end

-- How many of the tooltip's n lines are the data's own (the game's): the rest
-- are other addons'. Data with no lines of its own (the minimap's mail icon:
-- an empty list, the game writing the text itself), or none at all (an
-- addon's own tooltip), can't tell them apart: all are the card's. The first
-- line, the title, is always the card's.
function Rich.Own(data, n)
    local list = type(data) == "table" and data.lines or nil
    local own = type(list) == "table" and #list or 0
    -- A data line can add nothing (a recipe's empty spacer), so the last
    -- drawn line the data reaches is the true end, not the count of its lines.
    local last
    for _, line in ipairs(type(list) == "table" and list or {}) do
        local at = Read.Landed(line)
        if at and (not last or at > last) then last = at end
    end
    if last then own = last end
    if own == 0 then own = n end
    return math.max(1, math.min(own, n))
end

-- Plugins painting the card (API Paint kind "tooltip"): after each time
-- Daylight UI lays it out, never on the refills that change nothing.
function Rich.Painted(tip, s, p)
    local R = DUI.APIReport
    if not (R and R.Painting and R.Painting("tooltip")) then return end
    local info = p.paintInfo or {}
    p.paintInfo = info
    for k in pairs(info) do info[k] = nil end
    info.kind, info.style, info.unit = s.kind, "rich", s.unit
    if s.kind == "item" then
        local link = ns.Tooltip.ItemLink(tip, s.data)
        if not isSecret(link) then info.link = link end
    elseif s.kind == "spell" and type(s.data) == "table" then
        local id = s.data.id
        if not isSecret(id) and type(id) == "number" then info.spellID = id end
    end
    R.SetInfo(p, info)
    R.Painted("tooltip", p, info)
end

-- An epic item's light sweeps once as its card shows: not again on the
-- refills every 0.2 s, only for another item. Not on a compare tooltip.
function Rich.Sweep(tip, s, p, item)
    local key = item.color and ns.Tooltip.ItemLink(tip, s.data)
    if not key or s.swept == key or type(tip.CompareHeader) == "table" then return end
    s.swept = key
    if (item.quality or 0) >= ns.RichItems.EPIC then Panel.Sweep(p, item.color) end
end

-- Things in the world that aren't units: in a fight they share the pill.
function Rich.WorldThing(data)
    local t = type(data) == "table" and data.type or nil
    if isSecret(t) or t == nil then return false end
    local E = Enum and Enum.TooltipDataType
    return t == (E and E.Corpse or 3) or t == (E and E.Object or 4)
end

function Rich.Build(tip)
    local s = stateOf(tip)
    s.dirty = false
    if not Rich.On(tip) then return Rich.Off(tip) end
    local Tip = ns.Tooltip
    local p = Panel.For(tip)
    Panel.Level(p)
    local kind = Rich.Kind(s.data)
    local unit = kind == "unit" and Read.Unit(tip) or nil
    local refill, lastKind, lastSpell = s.refill, s.kind, s.spell
    s.refill = false
    s.unit, s.kind, s.spell = unit, kind, nil
    -- In a fight a unit is the pill by the cursor, the tooltip itself out of sight.
    s.world = not unit and Rich.WorldThing(s.data) or nil
    if (unit and ns.RichPill.Wanted(tip, unit)) or (s.world and ns.RichPill.WantedWorld(tip)) then
        if p:IsShown() then Panel.Release(p) end
        -- Nothing of the tooltip itself may draw under the pill: the client
        -- puts its alpha back on its own (its fade as the mouse leaves, a
        -- refill's Show), and its lines showed for a frame each time.
        Panel.Mute(p)
        Tip.ShowShell(tip, false)
        showBar(tip, false)
        s.pill = true
        s.lines = tip.NumLines and tip:NumLines() or nil
        if isSecret(s.lines) then s.lines = nil end
        ns.RichPill.Show(tip, unit)
        return
    end
    endPill(tip, s)
    local n, lines, secret = Read.Lines(tip, s.data)
    -- Under a map or PvP restriction every line of a unit's tooltip is secret
    -- (every dungeon, out of combat too). Its card is built from the unit
    -- alone then, so it looks the same as anywhere else.
    local fromUnit = secret and unit ~= nil
    s.fromUnit = fromUnit
    if fromUnit then n, lines, secret = 0, NO_LINES, false end
    s.seen = s.seen or {}
    -- A refill with the very same lines as the card shows (an item's, every
    -- 0.2 s): nothing to build. Rebuilding made heaps of garbage and the game
    -- stalled to clear it. Never for a unit or a spell: their cards also show
    -- things not in their lines (a target, a reaction, a cooldown).
    if refill and not unit and kind ~= "spell" and not secret and kind == lastKind and p:IsShown() and not p.chrome
        and Read.Same(s.seen, n, lines) then
        s.spell = lastSpell
        s.lines = tip.NumLines and tip:NumLines() or 0
        if isSecret(s.lines) then s.lines = nil end
        Panel.Mute(p)
        return
    end
    if secret then s.seen.n = nil else Read.Keep(s.seen, n, lines) end
    local light, fade = Rich.Light(tip, s.data, kind)
    -- Other addons' lines: everything after the data's own (an addon's own
    -- tooltip with no data has none). Read before the card, which places them;
    -- a plugin's tags join the header's.
    p.extraTags = nil
    if not secret then
        local f = ns.RichForeign.Read(p, tip, n, lines, Rich.Own(s.data, n), s.pieces)
        p.extraTags = #f.tags > 0 and f.tags or nil
        -- The item itself, for an addon read through its own API (ItemTree).
        local id = type(s.data) == "table" and s.data.id or nil
        f.itemID = not isSecret(id) and type(id) == "number" and id or nil
    end
    -- Something new while the card shows (not a refill of the same thing):
    -- its words fade in.
    local key = not secret and n >= 1 and lines[1].left and (kind .. "|" .. lines[1].left) or nil
    local fresh = p:IsShown() and key ~= nil and key ~= s.key
    s.key = key
    s.lines = tip.NumLines and tip:NumLines() or 0
    if isSecret(s.lines) then s.lines = nil end
    Panel.Begin(p, kind, light, fade)
    if secret then
        frameOnly(tip, s, p)
    else
        local item
        if unit and ns.RichPlayers.Is(unit) then
            ns.RichPlayers.Card(p, tip, unit, s.data, n, lines)
        elseif kind == "item" then
            item = ns.RichItems.Build(p, tip, s.data, n, lines, light, fade)
        elseif kind == "spell" and ns.RichSpells.Is(s.data) then
            s.spell = ns.RichSpells.Build(p, tip, s.data, n, lines)
        elseif unit then
            ns.RichWorld.Mob(p, tip, unit, s.data, n, lines, light)
        elseif s.world then
            ns.RichWorld.Object(p, tip, s.data, n, lines, light)
        else
            Rich.Generic(p, n, lines)
            Panel.Finish(p)
        end
        Panel.Mute(p)
        showBar(tip, unit == nil)
        p.fitTried = nil
        -- A card built from the unit keeps its own size when the tooltip's
        -- can't be read: the tooltip is out of sight under it anyway.
        if not Panel.Fit(p) and not fromUnit then
            frameOnly(tip, s, p)
        else
            if item then Rich.Sweep(tip, s, p, item) end
            if fresh then Panel.FadeBody(p) end
            Rich.Painted(tip, s, p)
        end
    end
    Tip.ShowShell(tip, false)
end
