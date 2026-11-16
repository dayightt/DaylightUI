-- Bar styles: a living fill on health and power bars (Flow, Tide...), picked
-- like the button glows. Nothing here reads a bar's value, so secret health
-- is fine: every layer sits in a clip frame that covers exactly the fill
-- (Style.FillClip) and the client runs the motion with animation groups, so
-- no Lua runs while a bar just sits there.

local _, DUI = ...
local Style = DUI.Style
local L = DUI.L

local BarFx = {}
DUI.BarFx = BarFx

BarFx.STYLES = { flow = L["Flow"], tide = L["Tide"] }
BarFx.ORDER = { "flow", "tide" }

-- Power bars on "By power type": the style that suits each power. A style not
-- built yet falls back to Flow.
BarFx.AUTO = { MANA = "flow", RAGE = "flow", ENERGY = "flow", FOCUS = "flow" }
BarFx.FLOW_LOOP = 9      -- seconds for the colors to roll one bar width
BarFx.TIDE_HEAL = 5      -- how fast the colors run right after a heal
BarFx.TIDE_HIT = 0.15    -- and right after a hit
BarFx.TIDE_BACK = 1.6    -- seconds to ease back to the usual speed

local worn = setmetatable({}, { __mode = "k" })    -- bar -> its state
local byFill = setmetatable({}, { __mode = "k" })  -- fill texture -> bar

-- A dropdown's values and order, "none" first.
function BarFx.Choices(auto)
    local values, order = { none = NONE or L["None"] }, { "none" }
    if auto then values.auto = L["By power type"]; order[2] = "auto" end
    for _, k in ipairs(BarFx.ORDER) do values[k] = BarFx.STYLES[k]; order[#order + 1] = k end
    return values, order
end

BarFx.KINDS = { "health", "power", "cast", "swing" }

-- A kind's setting (General > Bar Styles).
function BarFx.Get(kind, key)
    return DUI:Get("general", "barFx." .. kind .. "." .. key)
end

-- The style a tracked bar should wear now, from General's picks.
function BarFx.Pick(s)
    if not (DUI.Motion and DUI.Motion.On()) then return nil end
    if s.force then return BarFx.STYLES[s.force] and s.force or nil end
    if s.where == "plate" and not DUI:Get("general", "barFx.plates") then return nil end
    if s.where == "raid" and not DUI:Get("general", "barFx.raid") then return nil end
    local pick = BarFx.Get(s.kind, "style")
    if pick == "auto" then pick = BarFx.AUTO[s.power or ""] or "flow" end
    if not BarFx.STYLES[pick] then return nil end
    return pick
end

-- The two colors a style paints with: the bar's own (as last painted), the
-- accent, your class's pair or the picked pair. nil when they can't be known.
function BarFx.Colors(s)
    local mode = BarFx.Get(s.kind, "colors")
    local G = DUI.Gradients
    if mode == "accent" then
        local lo, hi = Style.AccentPair()
        if lo then return lo, hi end
        return G.PairFrom({ Style.Accent() })
    elseif mode == "class" then
        return G.PaintRGB(G.KeyFor("player"))
    elseif mode == "custom" then
        return BarFx.Get(s.kind, "colorA"), BarFx.Get(s.kind, "colorB")
    end
    return Style.FillColors(s.bar:GetStatusBarTexture())
end

local function setSpeedOf(s)
    local a = s.flow and s.flow.anim
    if a and a.SetAnimationSpeedMultiplier then a:SetAnimationSpeedMultiplier(math.max(0.01, s.speed or 1)) end
end

-- Flow: the bar's own gradient there and back twice, as four strips two bars
-- wide in all that slide one bar width and start over, so it never seams.
-- They lie on the bar itself, just over the fill and under everything else
-- drawn on it (hidden-class colors, a cast's "can't interrupt" color), masked
-- to the fill's shape. Strips are flat colors, or the Daylight sweep's own
-- image, which is smooth, so its mirrored copies meet cleanly; the bar's
-- texture lies over them once, still, in MOD, as over the real fill.
BarFx.WHITE = "Interface\\Buttons\\WHITE8X8"
BarFx.FILL_SUB = -3   -- the fill's sublevel while a style shows; strips and texture just above

local function buildFlow(s)
    local bar = s.bar
    local h = { strips = {}, slides = {} }
    h.anim = bar:CreateAnimationGroup()
    h.anim:SetLooping("REPEAT")
    for i = 1, 4 do
        local t = bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FILL_SUB + 1)
        Style.MaskToFill(bar, t)
        h.strips[i] = t
        local a = h.anim:CreateAnimation("Translation")
        a:SetTarget(t)
        a:SetDuration(BarFx.FLOW_LOOP)
        h.slides[i] = a
    end
    h.grain = bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FILL_SUB + 2)
    h.grain:SetBlendMode("MOD")
    Style.FollowFill(bar, h.grain)
    -- The game stops a frame's animations while it's hidden: start again on show.
    bar:HookScript("OnShow", function()
        if s.style and s.flow and s.flow.shown and not h.anim:IsPlaying() then h.anim:Play(); setSpeedOf(s) end
    end)
    s.flow = h
end

local function showFlow(h, on)
    h.shown = on
    for _, t in ipairs(h.strips) do t:SetShown(on) end
    h.grain:SetShown(on and h.grainOn == true)
end

local function layoutFlow(s)
    local h, bar = s.flow, s.bar
    local w = bar:GetWidth()
    if type(w) ~= "number" or w <= 0 then return end
    local ht = bar:GetHeight()
    if s.laidW == w and s.laidH == ht then return end
    s.laidW, s.laidH = w, ht
    local was = h.anim:IsPlaying()
    h.anim:Stop()
    for i, t in ipairs(h.strips) do
        t:ClearAllPoints()
        -- A pixel of overlap, so no gap shows where two strips meet.
        t:SetPoint("TOPLEFT", bar, "TOPLEFT", -w + (i - 1) * w / 2, 0)
        t:SetSize(w / 2 + 1, ht)
        h.slides[i]:SetOffset(w, 0)
    end
    if (was or s.style) and h.shown then h.anim:Play(); setSpeedOf(s) end
end

local function paintFlow(s)
    local h, bar = s.flow, s.bar
    local fill = bar:GetStatusBarTexture()
    local mode = BarFx.Get(s.kind, "colors")
    local grain, sweep = Style.BarGrainOf(bar)
    sweep = sweep and mode == "bar"
    local lo, hi
    if not sweep then
        lo, hi = BarFx.Colors(s)
        -- Colors the game keeps secret (a hidden class, health by percent in a
        -- fight) can't be copied: the plain fill stays.
        if not lo then showFlow(h, false); return false end
    end
    fill:SetDrawLayer("ARTWORK", BarFx.FILL_SUB)
    local alpha = BarFx.Get(s.kind, "strength") or 1
    for i, t in ipairs(h.strips) do
        local back = i % 2 == 0
        t:SetVertexColor(1, 1, 1, 1)
        if sweep then
            -- CLAMP, or the game blends each edge with the far one: a line at both ends.
            t:SetTexture(Style.GRADIENT_FILE, "CLAMP", "CLAMP")
            t:SetTexCoord(back and 1 or 0, back and 0 or 1, 0, 1)
            t:SetVertexColor(1, 1, 1, alpha)
        else
            t:SetTexture(BarFx.WHITE)
            t:SetTexCoord(0, 1, 0, 1)
            local a, b = back and hi or lo, back and lo or hi
            t:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], alpha), CreateColor(b[1], b[2], b[3], alpha))
        end
    end
    h.grainOn = grain ~= nil
    if grain then h.grain:SetTexture(grain, "CLAMP", "CLAMP") end
    showFlow(h, true)
    return true
end

local function setSpeed(s, k)
    local a = s.flow and s.flow.anim
    if a and a.SetAnimationSpeedMultiplier then a:SetAnimationSpeedMultiplier(math.max(0.01, k)) end
end

local function stop(s)
    if s.flow then
        s.flow.anim:Stop()
        showFlow(s.flow, false)
    end
    s.style = nil
end

local function apply(s)
    local style = BarFx.Pick(s)
    local bar = s.bar
    if style and bar.GetOrientation and bar:GetOrientation() == "VERTICAL" then style = nil end
    if not style then stop(s); return end
    s.style = style
    if not s.flow then buildFlow(s) end
    s.laidW = nil
    layoutFlow(s)
    s.speed = BarFx.Get(s.kind, "speed") or 1
    if paintFlow(s) then
        s.flow.anim:Play()
        setSpeed(s, s.speed)
    end
end

-- Follow a bar: kind "health" | "power" | "cast" | "swing", where nil | "raid" | "plate" (each
-- has its own switch). Call once; the bar then follows General's picks.
function BarFx.Track(bar, kind, where, unit, force)
    if type(bar) ~= "table" or not bar.GetStatusBarTexture then return end
    local s = worn[bar]
    if not s then
        s = { bar = bar }
        worn[bar] = s
        byFill[bar:GetStatusBarTexture()] = bar
        bar:HookScript("OnSizeChanged", function()
            if s.style and s.flow then layoutFlow(s) end
        end)
    end
    s.kind, s.where, s.unit, s.force = kind, where, unit, force
    apply(s)
end

-- The unit a tracked bar shows (Tide reacts to its hits and heals).
function BarFx.SetUnit(bar, unit)
    local s = worn[bar]
    if s then s.unit = unit end
end

-- A power bar's power token (MANA, RAGE...), for "By power type". A power bar
-- not followed yet (a frame's power bar moved out on its own) starts here.
function BarFx.SetPower(bar, token, where, unit)
    if DUI.IsSecret(token) then return end
    local s = worn[bar]
    if not s then
        BarFx.Track(bar, "power", where, unit)
        s = worn[bar]
        if not s then return end
    end
    if s.power == token then return end
    s.power = token
    if BarFx.Get(s.kind, "style") == "auto" then apply(s) end
end

function BarFx.StyleOf(bar)
    local s = worn[bar]
    return s and s.style
end

-- Style.NoteFill tells us a fill was repainted.
function BarFx.Painted(tex)
    local bar = byFill[tex]
    local s = bar and worn[bar]
    if s and s.style and s.flow then
        if paintFlow(s) and not s.flow.anim:IsPlaying() then s.flow.anim:Play() end
    end
end

-- Tide: a heal (dir > 0) speeds the roll up, a hit (dir < 0) nearly stops it,
-- then it eases back. Lua runs only while easing.
local easing = {}
local ticker
local function tick(_, dt)
    local any
    for s in pairs(easing) do
        s.easeT = s.easeT + dt
        local k = math.min(1, s.easeT / BarFx.TIDE_BACK)
        local e = 1 - (1 - k) * (1 - k)
        setSpeed(s, s.speed * (s.easeFrom + (1 - s.easeFrom) * e))
        if k >= 1 then easing[s] = nil else any = true end
    end
    if not any then ticker:SetScript("OnUpdate", nil) end
end

function BarFx.Kick(bar, dir)
    local s = worn[bar]
    if not (s and s.style == "tide" and s.flow and type(dir) == "number" and dir ~= 0) then return end
    if not BarFx.Get(s.kind, "react") then return end
    local size = BarFx.Get(s.kind, "reactSize") or 1
    s.easeFrom = dir > 0 and 1 + (BarFx.TIDE_HEAL - 1) * size or 1 - (1 - BarFx.TIDE_HIT) * math.min(1, size)
    s.easeT = 0
    easing[s] = true
    ticker = ticker or CreateFrame("Frame")
    BarFx.ticker = ticker
    ticker:SetScript("OnUpdate", tick)
end

-- Hits and heals come with UNIT_COMBAT (its action is plain; the amount isn't).
local KICK = { WOUND = -1, HEAL = 1 }
DUI.RegisterEvent("UNIT_COMBAT", function(_, unit, action)
    local dir = KICK[action]
    if not dir or type(unit) ~= "string" then return end
    for bar, s in pairs(worn) do
        if s.style == "tide" and s.unit == unit and s.kind == "health" and bar:IsVisible() then BarFx.Kick(bar, dir) end
    end
end)

function BarFx.Refresh()
    for _, s in pairs(worn) do apply(s) end
end

DUI.On("StyleChanged", BarFx.Refresh)

-- How many bars are easing back from a reaction (tests).
function BarFx.Easing()
    local n = 0
    for _ in pairs(easing) do n = n + 1 end
    return n
end

-- Samples: a bar of each kind in Daylight UI's look, following the picks
-- (options page, the setup guide, the question after an update). A sample
-- with demo on moves its value now and then, so reactions show.
BarFx.SAMPLE_KEYS = { health = nil, power = "MANA", cast = "CAST", swing = "SWING_MAIN" }
BarFx.SAMPLE_VALUES = { health = 0.72, power = 0.55, cast = 0.6, swing = 0.4 }
BarFx.DEMO_EVERY = 2.5

-- force: show this style whatever is picked (a setup guide card).
function BarFx.SampleBar(parent, kind, force)
    local holder = CreateFrame("Frame", nil, parent)
    Style.Shell(holder, {})
    local bar = Style.Bar(holder)
    bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(BarFx.SAMPLE_VALUES[kind] or 0.7)
    holder.bar = bar
    function holder.Paint()
        local key = BarFx.SAMPLE_KEYS[kind] or DUI.Gradients.KeyFor("player")
        DUI.Gradients.Paint(bar, key)
        Style.AngleFill(bar, "right", math.max(2, (holder:GetHeight() or 12) * 0.5))
    end
    holder:SetScript("OnSizeChanged", holder.Paint)
    holder.Paint()
    BarFx.Track(bar, kind, nil, kind == "health" and "player" or nil, force)
    return holder
end

-- A set of sample bars stacked, one per kind (nil = all four), with labels.
function BarFx.Sample(parent, kinds, opts)
    opts = opts or {}
    local s = { bars = {} }
    local f = CreateFrame("Frame", nil, parent)
    s.frame = f
    kinds = kinds or BarFx.KINDS
    local labels = { health = L["Health"], power = L["Power"], cast = L["Cast bar"], swing = L["Swing timer"] }
    for i, kind in ipairs(kinds) do
        local b = BarFx.SampleBar(f, kind, opts.force)
        b.kind = kind
        if not opts.bare then
            b.label = Style.Text(f, Style.SIZE.small, "LEFT")
            b.label:SetText(labels[kind])
            Style.InkText(b.label, "LABEL")
        end
        s.bars[i] = b
    end
    local rowH, gap, labelW = opts.height or 14, opts.gap or 10, opts.bare and 0 or 90
    function s.Refresh(width, maxHeight)
        f:SetSize(width, #s.bars * rowH + (#s.bars - 1) * gap)
        for i, b in ipairs(s.bars) do
            local y = -(i - 1) * (rowH + gap)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", labelW, y)
            b:SetSize(math.max(40, width - labelW - 8), rowH)
            if b.label then
                b.label:ClearAllPoints()
                b.label:SetPoint("LEFT", f, "TOPLEFT", 0, y - rowH / 2)
            end
        end
        return f:GetHeight()
    end
    -- Each bar jumps to its own settings when clicked (the options page).
    function s.Parts()
        local parts = {}
        for i, b in ipairs(s.bars) do
            parts[i] = { region = b, label = labels[b.kind], keys = { "barFx." .. b.kind .. ".style" } }
        end
        return parts
    end
    -- Now and then a hit or a heal, while shown, so a reaction can be seen.
    local wait, n = 0, 0
    f:SetScript("OnUpdate", function(_, dt)
        wait = wait + dt
        if wait < BarFx.DEMO_EVERY then return end
        wait, n = 0, n + 1
        local dir = n % 3 == 0 and 1 or -1
        for _, b in ipairs(s.bars) do
            local v = b.bar:GetValue() + dir * 0.12
            if v < 0.2 then v = 0.85 end
            Style.SetBarValue(b.bar, math.min(1, v))
            if b.kind == "health" then BarFx.Kick(b.bar, dir) end
        end
    end)
    return s
end

-- After an update, a one-time question: turn the bar styles on? Asked once per
-- account, only of players who had Daylight UI before (a new setup starts with
-- them on), with sample bars in the box so they can see what they'd get.
BarFx.ASK_DELAY = 6   -- after login: the setup guide and the tour ask first
BarFx.ASK_STYLE = "flow"

function BarFx.ShouldAsk()
    local DB = DUI.DB
    local root = DB.Root()
    if root.barFxAsked or DB.fresh or DB.Unsaved() then return false end
    if not (DUI.Motion and DUI.Motion.On()) then return false end
    for _, kind in ipairs(BarFx.KINDS) do
        if BarFx.Get(kind, "style") ~= "none" then return false end
    end
    return true
end

function BarFx.Ask()
    if not BarFx.ShouldAsk() then return end
    if DUI.InstallerUI and DUI.InstallerUI.IsShown() then return end
    if DUI.Tour and DUI.Tour.AskShown and DUI.Tour.AskShown() then
        C_Timer.After(BarFx.ASK_DELAY, BarFx.Ask)
        return
    end
    if InCombatLockdown() then return DUI.AfterCombat(BarFx.Ask, "barFx ask") end
    local sample
    DUI.Widgets.Ask({
        key = "barFx", title = L["Bar styles"],
        text = L["New: bars that move. Their colors roll slowly along your health, power, cast and swing bars. Turn them on? More styles are on General > Bar Styles."],
        yes = L["Turn them on"], no = L["Not now"],
        preview = {
            height = 2 * 14 + 10,
            show = function(holder)
                sample = sample or BarFx.Sample(holder, { "health", "power" }, { force = BarFx.ASK_STYLE })
                sample.frame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
                sample.Refresh(holder:GetWidth() > 0 and holder:GetWidth() or 340, 40)
                sample.frame:Show()
            end,
            hide = function() if sample then sample.frame:Hide() end end,
        },
        onYes = function()
            DUI.DB.Root().barFxAsked = true
            for _, kind in ipairs(BarFx.KINDS) do DUI:Set("general", "barFx." .. kind .. ".style", BarFx.ASK_STYLE) end
        end,
        onNo = function() DUI.DB.Root().barFxAsked = true end,
    })
end

DUI.RegisterEvent("PLAYER_LOGIN", function()
    C_Timer.After(BarFx.ASK_DELAY, BarFx.Ask)
end)
