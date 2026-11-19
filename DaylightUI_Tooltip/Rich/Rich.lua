-- The Rich / Simple switch and what fills the rich card. Simple is the skinned
-- game tooltip, untouched. Rich lays its own card (Rich/Panel.lua) over the main
-- tooltip after every fill: the data post-calls mark it, and it's built on show
-- and from the tooltip's update, before anything is drawn, so lines other
-- addons add after ours are in it.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local isSecret = DUI.IsSecret

local Rich = {}
ns.Rich = Rich

local Panel, Read = ns.RichPanel, ns.RichRead

-- The tooltips that get the card. The compare and clicked-item tooltips keep
-- the skinned look for now.
Rich.TIPS = { GameTooltip = true }

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
    local s = stateOf(tip)
    s.data, s.dirty = data, true
end

-- Emptied for new content: rebuilt from whatever comes next, data or not (an
-- addon's own AddLine tooltip has no data).
function Rich.Cleared(tip)
    local s = state[tip]
    if s then s.data, s.dirty = nil, true end
end

-- Shown: built now if a fill is waiting, then fitted.
function Rich.Shown(tip)
    if not Rich.On(tip) then return Rich.Off(tip) end
    local s = state[tip]
    if s and s.dirty then Rich.Build(tip) end
    local p = Panel.Get(tip)
    if p and p:IsShown() then Panel.Fit(p) end
end

-- Once a frame while shown (Tip.OnUpdate). Rebuilds when lines came or went
-- since the last build (another addon's AddLine) or the fight pill comes or
-- goes (a fight, Shift), fits the game's tooltip, and keeps a unit's bars live.
Rich.BAR_EVERY = 0.1
function Rich.Step(tip)
    local s = state[tip]
    if not s then return end
    if s.dirty then return Rich.Build(tip) end
    local Pill = ns.RichPill
    if s.unit and (s.pill == true) ~= Pill.Wanted(tip, s.unit) then return Rich.Build(tip) end
    if s.pill then return Pill.Step(tip, s.unit) end
    local p = Panel.Get(tip)
    if not (p and p:IsShown()) then return end
    local n = tip.NumLines and tip:NumLines()
    if not isSecret(n) and n ~= s.lines then return Rich.Build(tip) end
    if not Panel.Fit(p) then
        -- The size went secret since the build: the frame only.
        Panel.Unmute(p)
        Panel.Chrome(p)
        ns.Tooltip.ShowBar(true)
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
    if s then s.dirty, s.data, s.lines, s.unit = false, nil, nil, nil end
    Panel.Release(Panel.Get(tip))
    ns.Tooltip.ShowShell(tip, true)
    ns.Tooltip.ShowBar(true)
end

-- A setting changed: built again before the next draw, or put away.
function Rich.Refresh(tip)
    if Rich.On(tip) then
        stateOf(tip).dirty = true
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
    ns.Tooltip.ShowBar(true)
end

-- What the card's top light is: an item's quality, a unit's class or
-- reaction pair, else the accent.
function Rich.Light(tip, data, kind)
    local Tip = ns.Tooltip
    if kind == "item" then
        local q = Tip.Quality(Tip.ItemLink(tip, data))
        local r, g, b
        if q and q >= Tip.MIN_QUALITY then r, g, b = Tip.QualityColor(q) end
        if r then
            local lift = { math.min(1, r * 1.15 + 0.1), math.min(1, g * 1.15 + 0.1), math.min(1, b * 1.15 + 0.1) }
            return { lift, { r, g, b } }, true
        end
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

-- The tooltip's lines from line `from` on, in the card's look: a line with
-- two sides as a row, any other as a sentence, an empty one as a gap. The
-- colors go through the same rules as the skinned look (Tips.GameSide).
function Rich.Lines(p, n, lines, from)
    local Tips = DUI.Tips
    for i = from, n do
        local line = lines[i]
        if not line.left and not line.right then
            Panel.Gap(p, 4)
        elseif line.right then
            Panel.Row(p, line.left or "", line.right, valueColor(line))
        else
            local t, c = Tips.GameSide(line.left, line.hasLC and line.lc or nil)
            Panel.Text(p, t, c)
        end
    end
end

-- Any tooltip without a card of its own: the first line as the title, the
-- rest as Rich.Lines. A creature also gets its health in its reaction's pair.
function Rich.Generic(p, n, lines, unit)
    local first = lines[1]
    if n >= 1 and first.left then
        local color = first.hasLC and rgb(first.lc) or nil
        -- The game's white or yellow heading reads as the card's white title;
        -- a color of its own (quality, class) stays.
        local kind = color and DUI.Tips.GameColor(color[1], color[2], color[3])
        if kind == "white" or kind == "yellow" then color = nil end
        Panel.Header(p, { title = first.left, titleColor = color,
            right = first.right, rightColor = first.hasRC and rgb(first.rc) or nil })
    end
    Rich.Lines(p, n, lines, 2)
    if unit then
        local pair = ns.RichPlayers.ClassPair(unit)
        Panel.Gap(p, ns.RichPlayers.BEFORE_BARS)
        Panel.Bar(p, { unit = unit, health = true, h = 7, pair = pair })
    end
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
    s.unit = unit
    -- In a fight a unit is the pill by the cursor, the tooltip itself out of sight.
    if unit and ns.RichPill.Wanted(tip, unit) then
        if p:IsShown() then Panel.Release(p) end
        s.pill = true
        ns.RichPill.Show(tip, unit)
        return
    end
    endPill(tip, s)
    local light, fade = Rich.Light(tip, s.data, kind)
    local n, lines, secret = Read.Lines(tip, s.data)
    s.lines = tip.NumLines and tip:NumLines() or 0
    if isSecret(s.lines) then s.lines = nil end
    Panel.Begin(p, kind, light, fade)
    if secret then
        Panel.Unmute(p)
        Panel.Chrome(p)
        Tip.ShowBar(true)
    else
        if unit and ns.RichPlayers.Is(unit) then
            ns.RichPlayers.Card(p, tip, unit, s.data, n, lines)
        else
            Rich.Generic(p, n, lines, unit)
            Panel.Finish(p)
        end
        Panel.Mute(p)
        Tip.ShowBar(unit == nil)
        p.fitTried = nil
        if not Panel.Fit(p) then
            Panel.Unmute(p)
            Panel.Chrome(p)
            Tip.ShowBar(true)
        end
    end
    Tip.ShowShell(tip, false)
end
