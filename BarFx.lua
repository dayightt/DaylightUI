-- Bar styles: a living fill on health and power bars (Flow, Tide...), picked
-- like the button glows. Nothing here reads a bar's value, so secret health
-- is fine: every layer is laid over the fill and wears its masks, and the
-- client runs the motion with animation groups, so no Lua runs while a bar
-- just sits there.

local _, DUI = ...
local Style = DUI.Style
local L = DUI.L

local BarFx = {}
DUI.BarFx = BarFx

BarFx.STYLES = { flow = L["Flow"], tide = L["Tide"] }
BarFx.ORDER = { "flow", "tide" }

-- Power bars on "By power type": the style that suits each power. A style not
-- built yet falls back to Flow.
BarFx.RETIRED = {}   -- a style taken out -> the one shown instead (BarFxStyles.lua)
BarFx.AUTO = { MANA = "flow", RAGE = "flow", ENERGY = "flow", FOCUS = "flow" }
BarFx.FLOW_LOOP = 9      -- seconds for the colors to roll one bar width

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

-- Each bar's settings live with the module that owns it (a frame's
-- barFx.health, a cast bar's barFx...), one table per bar like this. A key
-- the table doesn't have reads as here.
BarFx.DEFAULTS = { style = "none", speed = 1, strength = 1, colors = "bar",
    colorA = { 0.25, 0.45, 0.85 }, colorB = { 0.95, 0.6, 0.3 }, react = true, reactSize = 1 }

-- A fresh copy of the defaults, for a module's own defaults.
function BarFx.Defaults()
    local t = {}
    for k, v in pairs(BarFx.DEFAULTS) do t[k] = type(v) == "table" and { v[1], v[2], v[3] } or v end
    return t
end

-- What a module hands Track as cfg: read() returns the bar's settings table
-- at the moment it's asked (so a profile change or another raid size is
-- followed), or nil.
function BarFx.Reader(read)
    return function(key)
        local t = read()
        if type(t) == "table" then return t[key] end
    end
end

-- A tracked bar's setting.
function BarFx.Get(s, key)
    local v = s.cfg and s.cfg(key)
    if v == nil then v = BarFx.DEFAULTS[key] end
    return v
end

-- The style a tracked bar should wear now, from its own settings.
function BarFx.Pick(s)
    if not (DUI.Motion and DUI.Motion.On()) then return nil end
    if s.force then return BarFx.STYLES[s.force] and s.force or nil end
    local pick = BarFx.Get(s, "style")
    pick = BarFx.RETIRED[pick] or pick
    if pick == "auto" then pick = BarFx.AUTO[s.power or ""] or "flow" end
    if not BarFx.STYLES[pick] then return nil end
    return pick
end

-- The two colors a style paints with: the bar's own (as last painted), the
-- accent, your class's pair or the picked pair. nil when they can't be known.
function BarFx.Colors(s)
    local mode = BarFx.Get(s, "colors")
    local G = DUI.Gradients
    if mode == "accent" then
        local lo, hi = Style.AccentPair()
        if lo then return lo, hi end
        return G.PairFrom({ Style.Accent() })
    elseif mode == "class" then
        return G.PaintRGB(G.KeyFor("player"))
    elseif mode == "custom" then
        return BarFx.Get(s, "colorA"), BarFx.Get(s, "colorB")
    end
    return Style.FillColors(s.bar:GetStatusBarTexture())
end

local function setSpeedOf(s)
    local a = s.flow and s.flow.anim
    if a and a.SetAnimationSpeedMultiplier then a:SetAnimationSpeedMultiplier(math.max(0.01, s.speed or 1)) end
end

-- Flow: the bar's own two colors rolling along it. A base in the first color
-- and a soft wave in the second over it (barfx-wave.png, eased on a cosine, so
-- the turns have no crease), or on a Daylight sweep bar the sweep itself there
-- and back (barfx-sweep.png). Both are flipbook sheets the game steps through,
-- so nothing moves out of the fill: each layer is laid exactly over it and
-- wears the fill's own masks (its moving angled edge, and the bar's still ends
-- through Style.ClipLike), as the bar's texture layer does. They sit just over
-- the fill and under everything else drawn on the bar (hidden-class colors, a
-- cast's "can't interrupt" color).
BarFx.WHITE = "Interface\\Buttons\\WHITE8X8"
BarFx.WAVE = DUI.MEDIA .. "barfx-wave.png"
BarFx.SWEEP = DUI.MEDIA .. "barfx-sweep.png"
BarFx.FRAMES = 256   -- rows in the sheets (tools/make_barfx.py)
BarFx.FILL_SUB = -7   -- the fill's sublevel while a style shows; Flow just above, lights over it (BarFx.FX_SUB), the bar's overlays from 1
BarFx.FX_SUB = -1

local function flipbook(group, t)
    local a = group:CreateAnimation("FlipBook")
    a:SetTarget(t)
    a:SetDuration(BarFx.FLOW_LOOP)
    a:SetFlipBookRows(BarFx.FRAMES)
    a:SetFlipBookColumns(1)
    a:SetFlipBookFrames(BarFx.FRAMES)
    a:SetFlipBookFrameWidth(0)
    a:SetFlipBookFrameHeight(0)
    return a
end

local function buildFlow(s)
    local bar = s.bar
    local h = {}
    h.anim = bar:CreateAnimationGroup()
    h.anim:SetLooping("REPEAT")
    h.base = bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FILL_SUB + 1)
    h.wave = bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FILL_SUB + 2)
    h.grain = bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FILL_SUB + 3)
    h.grain:SetBlendMode("MOD")
    h.layers = { h.base, h.wave, h.grain }
    for _, t in ipairs(h.layers) do Style.FollowFill(bar, t) end
    h.baseBook = flipbook(h.anim, h.base)
    flipbook(h.anim, h.wave)
    -- The game stops a frame's animations while it's hidden: start again on show.
    bar:HookScript("OnShow", function()
        if s.style and s.flow and s.flow.shown then
            h.anim:Stop()
            h.anim:Play()
            setSpeedOf(s)
        end
    end)
    s.flow = h
end

local function showFlow(h, on)
    h.shown = on
    h.base:SetShown(on)
    h.wave:SetShown(on and h.waveOn == true)
    h.grain:SetShown(on and h.grainOn == true)
end

-- Laid over the fill, so a size change needs nothing.
local function layoutFlow() end

local function paintFlow(s)
    local h, bar = s.flow, s.bar
    local fill = bar:GetStatusBarTexture()
    local mode = BarFx.Get(s, "colors")
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
    -- Cut exactly like the fill: its angled end and the bar's still ends, which
    -- may be set only after the bar was first laid out.
    for _, t in ipairs(h.layers) do Style.SameMasks(t, fill) end
    local alpha = BarFx.Get(s, "strength") or 1
    -- CLAMP, or the game blends each edge with the far one: a line at both ends.
    if sweep then
        h.base:SetTexture(BarFx.SWEEP, "CLAMP", "CLAMP")
        h.baseBook:SetDuration(BarFx.FLOW_LOOP)
        h.base:SetVertexColor(1, 1, 1, alpha)
        h.waveOn = false
    else
        h.base:SetTexture(BarFx.WHITE)
        h.base:SetTexCoord(0, 1, 0, 1)
        h.base:SetVertexColor(lo[1], lo[2], lo[3], alpha)
        h.wave:SetTexture(BarFx.WAVE, "CLAMP", "CLAMP")
        h.wave:SetVertexColor(hi[1], hi[2], hi[3], alpha)
        h.waveOn = true
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

-- More styles plug in here (BarFxStyles.lua): BarFx.Add(key, label, def), def =
-- { flow = true (Flow's rolling colors under it), build(s) -> piece, layout(s, p, w, h),
--   paint(s, p, lo, hi, alpha), show(s, p, on), kick(s, p, dir, size) }.
-- A piece is built the first time its style is picked, then kept.
BarFx.DEFS = {}
function BarFx.Add(key, label, def)
    if not BarFx.STYLES[key] then BarFx.ORDER[#BarFx.ORDER + 1] = key end
    BarFx.STYLES[key] = label
    BarFx.DEFS[key] = def
end

local function flowFor(style)
    local def = BarFx.DEFS[style]
    return style == "flow" or (def ~= nil and def.flow == true)
end

local function hidePieces(s, keep)
    for key, p in pairs(s.pieces or {}) do
        if key ~= keep then BarFx.DEFS[key].show(s, p, false) end
    end
end

local function layoutPiece(s)
    local def = BarFx.DEFS[s.style or ""]
    local p = def and s.pieces and s.pieces[s.style]
    if not p then return end
    local w, h = s.bar:GetWidth(), s.bar:GetHeight()
    if type(w) == "number" and w > 0 then def.layout(s, p, w, h) end
end

local function paintPiece(s)
    local def = BarFx.DEFS[s.style or ""]
    local p = def and s.pieces and s.pieces[s.style]
    if not p then return end
    local lo, hi = BarFx.Colors(s)
    local alpha = BarFx.Get(s, "strength") or 1
    def.show(s, p, def.paint(s, p, lo, hi, alpha) ~= false)
end

local function stop(s)
    if s.flow then
        s.flow.anim:Stop()
        showFlow(s.flow, false)
    end
    hidePieces(s)
    s.style = nil
end

local function apply(s)
    local style = BarFx.Pick(s)
    local bar = s.bar
    if style and bar.GetOrientation and bar:GetOrientation() == "VERTICAL" then style = nil end
    if not style then stop(s); return end
    s.style = style
    s.speed = BarFx.Get(s, "speed") or 1
    -- The fill goes to the bottom of its layer, so every style's layers draw over it.
    s.bar:GetStatusBarTexture():SetDrawLayer("ARTWORK", BarFx.FILL_SUB)
    if flowFor(style) then
        if not s.flow then buildFlow(s) end
        s.laidW = nil
        layoutFlow(s)
        if paintFlow(s) then
            s.flow.anim:Play()
            setSpeed(s, s.speed)
        end
    elseif s.flow then
        s.flow.anim:Stop()
        showFlow(s.flow, false)
    end
    hidePieces(s, style)
    local def = BarFx.DEFS[style]
    if def then
        s.pieces = s.pieces or {}
        s.pieces[style] = s.pieces[style] or def.build(s)
        layoutPiece(s)
        paintPiece(s)
    end
end

-- Follow a bar: kind "health" | "power" | "cast" | "swing", where nil | "raid" |
-- "plate", cfg = the bar's own settings (a function of a key, BarFx.Reader).
-- Call again with new ones; BarFx.Apply after they change.
function BarFx.Track(bar, kind, where, unit, force, cfg)
    if type(bar) ~= "table" or not bar.GetStatusBarTexture then return end
    local s = worn[bar]
    if not s then
        s = { bar = bar }
        worn[bar] = s
        byFill[bar:GetStatusBarTexture()] = bar
        bar:HookScript("OnSizeChanged", function()
            if s.style and s.flow and flowFor(s.style) then layoutFlow(s) end
            if s.style then layoutPiece(s) end
        end)
    end
    s.kind, s.where, s.unit, s.force, s.cfg = kind, where, unit, force, cfg
    apply(s)
end

-- Puts a tracked bar in step with its settings again (after they changed).
function BarFx.Apply(bar)
    local s = worn[bar]
    if s then apply(s) end
end

-- The unit a tracked bar shows (Tide reacts to its hits and heals).
function BarFx.SetUnit(bar, unit)
    local s = worn[bar]
    if s then s.unit = unit end
end

-- A power bar's power token (MANA, RAGE...), for "By power type". A power bar
-- not followed yet (a frame's power bar moved out on its own) starts here.
function BarFx.SetPower(bar, token, where, unit, cfg)
    if DUI.IsSecret(token) then return end
    local s = worn[bar]
    if not s then
        BarFx.Track(bar, "power", where, unit, nil, cfg)
        s = worn[bar]
        if not s then return end
    elseif cfg and s.cfg ~= cfg then
        -- A frame's power bar can be another bar now (moved out on its own).
        s.cfg, s.power = cfg, nil
    end
    if s.power == token then return end
    s.power = token
    if BarFx.Get(s, "style") == "auto" then apply(s) end
end

-- Style.AngleFill tells us a fill's angled end changed: lights pinned to the
-- end lean with it.
function BarFx.Angled(bar)
    local s = worn[bar]
    if not (s and s.style and s.pieces) then return end
    -- AngleFill runs at every layout of a frame; only a new angle matters.
    local side, cut, under = Style.GetFillAngle(bar)
    if s.angleSide == side and s.angleCut == cut and s.angleUnder == under then return end
    s.angleSide, s.angleCut, s.angleUnder = side, cut, under
    layoutPiece(s)
end

function BarFx.StyleOf(bar)
    local s = worn[bar]
    return s and s.style
end

-- Style.NoteFill tells us a fill was repainted.
function BarFx.Painted(tex)
    local bar = byFill[tex]
    local s = bar and worn[bar]
    if s and s.style and s.flow and flowFor(s.style) then
        if paintFlow(s) and not s.flow.anim:IsPlaying() then s.flow.anim:Play() end
    end
    if s and s.style then paintPiece(s) end
end

-- A heal (dir > 0) or a hit (dir < 0) on a style that reacts to them.
function BarFx.Kick(bar, dir)
    local s = worn[bar]
    if not (s and s.style and type(dir) == "number" and dir ~= 0) then return end
    if not BarFx.Get(s, "react") then return end
    local size = BarFx.Get(s, "reactSize") or 1
    local def = BarFx.DEFS[s.style]
    if def and def.kick then
        local p = s.pieces and s.pieces[s.style]
        if p then def.kick(s, p, dir, size) end
    end
end

-- Hits and heals come with UNIT_COMBAT (its action is plain; the amount isn't).
local KICK = { WOUND = -1, HEAL = 1 }
DUI.RegisterEvent("UNIT_COMBAT", function(_, unit, action)
    local dir = KICK[action]
    if not dir or type(unit) ~= "string" then return end
    for bar, s in pairs(worn) do
        local reacts = BarFx.DEFS[s.style or ""] and BarFx.DEFS[s.style].kick
        if reacts and s.unit == unit and s.kind == "health" and bar:IsVisible() then BarFx.Kick(bar, dir) end
    end
end)

function BarFx.Refresh()
    for _, s in pairs(worn) do apply(s) end
end

-- An animation started behind a loading screen can stay "playing" without
-- ever moving (seen in game after a /reload), and Play does nothing to one
-- that thinks it's playing. Once the screen is gone, each one starts over.
function BarFx.Restart()
    for _, s in pairs(worn) do
        if s.style then
            local h = s.flow
            if h and h.shown and flowFor(s.style) then
                h.anim:Stop()
                h.anim:Play()
                setSpeed(s, s.speed)
            end
            local p = s.pieces and s.pieces[s.style]
            if p and p.on and p.anim then
                p.anim:Stop()
                BarFx.DEFS[s.style].show(s, p, true)
            end
        end
    end
end
DUI.RegisterEvent("LOADING_SCREEN_DISABLED", BarFx.Restart)

DUI.On("StyleChanged", BarFx.Refresh)

-- Samples: a bar of each kind in Daylight UI's look, following the picks
-- (options page, the setup guide, the question after an update). A sample
-- with demo on moves its value now and then, so reactions show.
BarFx.SAMPLE_KEYS = { health = nil, power = "MANA", cast = "CAST", swing = "SWING_MAIN" }
BarFx.SAMPLE_VALUES = { health = 0.72, power = 0.55, cast = 0.6, swing = 0.4 }
BarFx.DEMO_EVERY = 2.5

-- force: show this style whatever is picked (a setup guide card). cfg: the
-- settings it follows (nil = the defaults).
function BarFx.SampleBar(parent, kind, force, cfg)
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
    BarFx.Track(bar, kind, nil, kind == "health" and "player" or nil, force, cfg)
    return holder
end

-- A set of sample bars stacked, one per kind (nil = all four), with labels.
-- opts.cfg(kind) = the settings each kind's bar follows.
function BarFx.Sample(parent, kinds, opts)
    opts = opts or {}
    local s = { bars = {} }
    local f = CreateFrame("Frame", nil, parent)
    s.frame = f
    kinds = kinds or BarFx.KINDS
    local labels = { health = L["Health"], power = L["Power"], cast = L["Cast bar"], swing = L["Swing timer"] }
    for i, kind in ipairs(kinds) do
        local b = BarFx.SampleBar(f, kind, opts.force, opts.cfg and opts.cfg(kind))
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
    -- Puts the bars in step with their settings again (an options row's update).
    function s.Apply()
        for _, b in ipairs(s.bars) do BarFx.Apply(b.bar) end
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

-- Where bars start in a style: every new setup (DB.StandardStart) and a Yes
-- to the question. Each path is one bar's settings table in that module.
-- Raid tiles and nameplates stay plain: forty moving bars in a fight is busy.
BarFx.HOMES = {
    UnitFrames = {
        "player.barFx.health", "player.barFx.power", "target.barFx.health", "target.barFx.power",
        "focus.barFx.health", "focus.barFx.power", "pet.barFx.health", "pet.barFx.power",
        "targettarget.barFx.health", "targettarget.barFx.power", "focustarget.barFx.health", "focustarget.barFx.power",
        "party.barFx.health", "party.barFx.power", "partyPet.barFx.health", "partyPet.barFx.power",
        "partyTarget.barFx.health", "partyTarget.barFx.power", "arena.barFx.health", "arena.barFx.power",
        "personal.barFx.health", "personal.barFx.power",
        "playerCastbar.barFx", "targetCastbar.barFx", "focusCastbar.barFx", "partyCastbar.barFx", "swing.barFx",
    },
    ActionBars = { "cdmBarFx" },
}

-- The style keys of every home but skip (the setup guide's card sets one and
-- these along with it): a key of module itself, the others as { module, key }.
function BarFx.StyleKeys(module, skip)
    local keys = {}
    for name, paths in pairs(BarFx.HOMES) do
        for _, path in ipairs(paths) do
            local key = path .. ".style"
            if name ~= module then
                keys[#keys + 1] = { name, key }
            elseif key ~= skip then
                keys[#keys + 1] = key
            end
        end
    end
    return keys
end

-- Writes style into every home of a profile's modules table.
function BarFx.StartIn(modules, style)
    for name, paths in pairs(BarFx.HOMES) do
        if type(modules[name]) ~= "table" then modules[name] = {} end
        for _, path in ipairs(paths) do
            local t = modules[name]
            for part in string.gmatch(path, "[^%.]+") do
                if type(t[part]) ~= "table" then t[part] = {} end
                t = t[part]
            end
            t.style = style
        end
    end
    return modules
end

function BarFx.ShouldAsk()
    local DB = DUI.DB
    local root = DB.Root()
    if root.barFxAsked or DB.fresh or DB.Unsaved() then return false end
    if not (DUI.Motion and DUI.Motion.On()) then return false end
    -- Nothing to ask about with those modules off (their settings read nil).
    local seen = false
    for name, paths in pairs(BarFx.HOMES) do
        for _, path in ipairs(paths) do
            local v = DUI:Get(name, path .. ".style")
            if v ~= nil and v ~= "none" then return false end
            seen = seen or v ~= nil
        end
    end
    return seen
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
        text = L["New: bars that move. Their colors roll slowly along your health, power, cast and swing bars. Turn them on? Each frame's page has more styles under Bar animation."],
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
            for name, paths in pairs(BarFx.HOMES) do
                if DUI:GetModule(name) then
                    for _, path in ipairs(paths) do DUI:Set(name, path .. ".style", BarFx.ASK_STYLE) end
                end
            end
        end,
        onNo = function() DUI.DB.Root().barFxAsked = true end,
    })
end

-- Bar styles were briefly one General setting per kind of bar (general.barFx).
-- A profile that still has it gets each pick moved onto its bars, then it's gone.
function BarFx.MoveFromGeneral()
    local g = DUI.DB.General()
    local old = type(g) == "table" and g.barFx
    if type(old) ~= "table" then return end
    g.barFx = nil
    for name, paths in pairs(BarFx.HOMES) do
        if DUI:GetModule(name) then
            for _, path in ipairs(paths) do
                local kind = string.match(path, "%.(%a+)$")
                if kind == "barFx" then kind = string.find(path, "^swing") and "swing" or "cast" end
                local style = type(old[kind]) == "table" and old[kind].style
                if type(style) == "string" and style ~= "none" and DUI:Get(name, path .. ".style") == "none" then
                    DUI:Set(name, path .. ".style", style)
                end
            end
        end
    end
end

DUI.RegisterEvent("PLAYER_LOGIN", function()
    BarFx.MoveFromGeneral()
    C_Timer.After(BarFx.ASK_DELAY, BarFx.Ask)
end)
