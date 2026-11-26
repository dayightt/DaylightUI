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

-- Each style's name, looked up when shown (a picked language goes on after load).
BarFx.STYLES = { flow = function() return L["Flow"] end, tide = function() return L["Tide"] end }
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
    for _, k in ipairs(BarFx.ORDER) do
        local label = BarFx.STYLES[k]
        values[k] = type(label) == "function" and label() or label
        order[#order + 1] = k
    end
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

-- A solid bar has one color twice, and rolling a color over itself shows no
-- movement at all. Its wave then runs a lighter shade of that color.
BarFx.LIFT = 0.4   -- how far toward white the lighter shade goes
local function twoColors(lo, hi)
    if not (lo and hi) or lo[1] ~= hi[1] or lo[2] ~= hi[2] or lo[3] ~= hi[3] then return lo, hi end
    local k = BarFx.LIFT
    return lo, { lo[1] + (1 - lo[1]) * k, lo[2] + (1 - lo[2]) * k, lo[3] + (1 - lo[3]) * k }
end

-- The two colors a style paints with: the bar's own (as last painted), the
-- accent, your class's pair or the picked pair. nil when they can't be known.
function BarFx.Colors(s)
    local mode = BarFx.Get(s, "colors")
    local G = DUI.Gradients
    if mode == "accent" then
        local lo, hi = Style.AccentPair()
        if lo then return lo, hi end
        return twoColors(G.PairFrom({ Style.Accent() }))
    elseif mode == "class" then
        return twoColors(G.PaintRGB(G.KeyFor("player")))
    elseif mode == "custom" then
        return twoColors(BarFx.Get(s, "colorA"), BarFx.Get(s, "colorB"))
    end
    return twoColors(Style.FillColors(s.bar:GetStatusBarTexture()))
end

-- Every color Flow rolls when there are more than two (a custom gradient
-- accent), left to right, or nil.
function BarFx.Stops(s)
    local mode = BarFx.Get(s, "colors")
    if mode == "accent" then return Style.AccentStops() end
    if mode == "bar" then return Style.FillStops(s.bar:GetStatusBarTexture()) end
end

-- Flow's animation groups: the main one, then one per extra wave.
local function groupsOf(h)
    local list = { h.anim }
    for i = 1, h.waves or 0 do list[#list + 1] = h.extra[i].anim end
    return list
end

local function setSpeed(s, k)
    if not s.flow then return end
    for _, a in ipairs(groupsOf(s.flow)) do
        if a.SetAnimationSpeedMultiplier then a:SetAnimationSpeedMultiplier(math.max(0.01, k)) end
    end
end

local function setSpeedOf(s) setSpeed(s, s.speed or 1) end

local function stopFlow(h)
    h.playing = (h.playing or 0) + 1   -- drops the extra waves still waiting to start
    h.anim:Stop()
    for i = 1, #(h.extra or {}) do
        local e = h.extra[i]
        e.anim:Stop()
        -- A flipbook that isn't playing draws its whole sheet squashed into
        -- the bar, so a wave stays hidden until its turn to start.
        e.live = nil
        e.tex:Hide()
    end
end

-- Starts Flow over. Each extra wave starts its share of the loop later, so
-- the colors chase each other evenly along the bar; the client then keeps
-- them in step, at the same speed, with no Lua running.
local function playFlow(s)
    local h = s.flow
    stopFlow(h)
    h.anim:Play()
    setSpeedOf(s)
    local n, token = h.waves or 0, h.playing
    for i = 1, n do
        local e = h.extra[i]
        local wait = BarFx.FLOW_LOOP * i / (n + 1) / math.max(0.01, s.speed or 1)
        C_Timer.After(wait, function()
            if h.playing ~= token or not h.shown or h.isSweep or i > (h.waves or 0) then return end
            e.anim:Play()
            setSpeedOf(s)
            e.live = true
            e.tex:SetAlpha(0)
            e.tex:Show()
            DUI.Motion.AlphaTo(e.tex, 1, DUI.Motion.SLOW)
        end)
    end
end

-- Flow: the bar's own two colors rolling along it, or on a Daylight sweep bar
-- the sweep itself there and back (barfx-sweep.png). The waves are flipbook
-- sheets the game steps through, so nothing moves out of the fill: each layer
-- is laid exactly over it and wears the fill's own masks (its moving angled
-- edge, and the bar's still ends), as the bar's texture layer does. They sit
-- just over the fill and under everything else drawn on the bar (hidden-class
-- colors, a cast's "can't interrupt" color).
-- The bar's texture has to show all along the bar, crest and trough: a plain
-- wave laid over it hid its shading wherever the wave stood, so every bar
-- texture looked the same. So the base wears the bar's own texture in what the
-- two colors share (the lower of each channel), and two soft waves ADD the
-- rest on top: the second color's share on a cosine (barfx-wave.png, eased, so
-- the turns have no crease) and the first's on its mirror (barfx-wave-ebb.png,
-- one minus the wave). The colors still roll exactly between the two, with
-- the texture's shading under them.
-- No layer is drawn in MOD: one with a mask wipes out what lies under it where
-- the mask cuts it away, so the world showed through past the fill's angled
-- edge (seen in game).
BarFx.WHITE = "Interface\\Buttons\\WHITE8X8"
BarFx.WAVE = DUI.MEDIA .. "barfx-wave.png"
BarFx.WAVE_EBB = DUI.MEDIA .. "barfx-wave-ebb.png"
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
    local h = { bar = bar }
    h.anim = bar:CreateAnimationGroup()
    h.anim:SetLooping("REPEAT")
    h.base = bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FILL_SUB + 1)
    h.sweep = bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FILL_SUB + 1)
    h.wave = bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FILL_SUB + 2)
    h.ebb = bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FILL_SUB + 2)
    h.wave:SetBlendMode("ADD")
    h.ebb:SetBlendMode("ADD")
    h.layers = { h.base, h.sweep, h.wave, h.ebb }
    for _, t in ipairs(h.layers) do Style.FollowFill(bar, t) end
    flipbook(h.anim, h.sweep)
    flipbook(h.anim, h.wave)
    flipbook(h.anim, h.ebb)
    -- The game stops a frame's animations while it's hidden: start again on show.
    h.extra, h.waves = {}, 0
    bar:HookScript("OnShow", function()
        if s.style and s.flow and s.flow.shown then playFlow(s) end
    end)
    s.flow = h
end

-- The i-th extra wave (a color after the second), made the first time a bar
-- needs it, then kept.
local function extraWave(s, i)
    local h = s.flow
    local e = h.extra[i]
    if e then return e end
    e = { anim = s.bar:CreateAnimationGroup() }
    e.anim:SetLooping("REPEAT")
    -- Laid over the added pair: drawn under it, the pair would add onto it.
    e.tex = s.bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FILL_SUB + 3)
    Style.FollowFill(s.bar, e.tex)
    flipbook(e.anim, e.tex)
    h.extra[i] = e
    h.layers[#h.layers + 1] = e.tex
    return e
end

local function showFlow(h, on)
    local was = h.shown
    h.shown = on
    h.base:SetShown(on and not h.isSweep)
    h.sweep:SetShown(on and h.isSweep == true)
    h.wave:SetShown(on and not h.isSweep)
    h.ebb:SetShown(on and not h.isSweep and h.ebbOn == true)
    for i, e in ipairs(h.extra or {}) do
        e.tex:SetShown(on and not h.isSweep and i <= (h.waves or 0) and e.live == true)
    end
    -- A fill in three or more colors hides its pieces under Flow, and shows them again after.
    if was ~= on then Style.LayBarStops(h.bar) end
end

-- Laid over the fill, so a size change needs nothing.
local function layoutFlow() end

local function paintFlow(s)
    local h, bar = s.flow, s.bar
    local fill = bar:GetStatusBarTexture()
    local mode = BarFx.Get(s, "colors")
    local grain, sweep = Style.BarGrainOf(bar)
    sweep = sweep and mode == "bar"
    local lo, hi, stops
    if not sweep then
        lo, hi = BarFx.Colors(s)
        -- Colors the game keeps secret (a hidden class, health by percent in a
        -- fight) can't be copied: the plain fill stays.
        if not lo then showFlow(h, false); return false end
        stops = BarFx.Stops(s)
        if stops then lo, hi = stops[1], stops[2] end
    end
    -- Past two colors, each one more rolls as a wave of its own.
    local waves = stops and #stops - 2 or 0
    for i = 1, waves do extraWave(s, i) end
    local more = waves ~= (h.waves or 0)
    if more then stopFlow(h) end
    h.waves = waves
    fill:SetDrawLayer("ARTWORK", BarFx.FILL_SUB)
    -- Cut exactly like the fill: its angled end and the bar's still ends, which
    -- may be set only after the bar was first laid out.
    for _, t in ipairs(h.layers) do Style.SameMasks(t, fill) end
    local alpha = BarFx.Get(s, "strength") or 1
    -- CLAMP, or the game blends each edge with the far one: a line at both ends.
    h.isSweep = sweep
    if sweep then
        h.sweep:SetTexture(BarFx.SWEEP, "CLAMP", "CLAMP")
        h.sweep:SetVertexColor(1, 1, 1, alpha)
    else
        -- The bar's own texture, so its shading stays, in what both colors
        -- share; the waves add each color's own part over it.
        local r, g, b = math.min(lo[1], hi[1]), math.min(lo[2], hi[2]), math.min(lo[3], hi[3])
        h.base:SetTexture(grain or BarFx.WHITE, "CLAMP", "CLAMP")
        h.base:SetVertexColor(r, g, b, alpha)
        h.wave:SetTexture(BarFx.WAVE, "CLAMP", "CLAMP")
        h.wave:SetVertexColor(hi[1] - r, hi[2] - g, hi[3] - b, alpha)
        -- A lighter shade of one color adds nothing on the ebb: no layer then.
        h.ebbOn = lo[1] > r or lo[2] > g or lo[3] > b
        h.ebb:SetTexture(BarFx.WAVE_EBB, "CLAMP", "CLAMP")
        h.ebb:SetVertexColor(lo[1] - r, lo[2] - g, lo[3] - b, alpha)
        for i = 1, waves do
            local t, c = h.extra[i].tex, stops[i + 2]
            t:SetTexture(BarFx.WAVE, "CLAMP", "CLAMP")
            t:SetVertexColor(c[1], c[2], c[3], alpha)
        end
    end
    showFlow(h, true)
    return true, more
end

-- More styles plug in here (BarFxStyles.lua): BarFx.Add(key, label, def), label a
-- string or a function returning it (looked up when shown), def =
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
        stopFlow(s.flow)
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
        if paintFlow(s) then playFlow(s) end
    elseif s.flow then
        stopFlow(s.flow)
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
    if not s then return end
    -- Another unit: a reaction still playing was the last one's.
    if s.unit ~= unit then BarFx.ClearReaction(bar) end
    s.unit = unit
end

-- A bar now shows someone else under the same unit token (a new target, a
-- nameplate handed to another mob): a style's reaction in flight stops.
function BarFx.ClearReaction(bar)
    local s = worn[bar]
    if not (s and s.pieces) then return end
    for key, p in pairs(s.pieces) do
        local def = BarFx.DEFS[key]
        if def and def.clearReaction then def.clearReaction(s, p) end
    end
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

-- Whether Flow covers the bar's fill right now.
function BarFx.FlowShown(bar)
    local s = worn[bar]
    return s ~= nil and s.flow ~= nil and s.flow.shown == true
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
        local on, more = paintFlow(s)
        if on and (more or not s.flow.anim:IsPlaying()) then playFlow(s) end
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
            if h and h.shown and flowFor(s.style) then playFlow(s) end
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
