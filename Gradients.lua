-- Hand-picked color pairs (a deep shade and a light one) that bars fill
-- with, shared by every module. A pair is registered under a key (a class
-- token, a reaction...), and the player's changes live in
-- general.gradients.colors. New kinds are just more Register calls.

local _, DUI = ...
local Style = DUI.Style

local Gradients = {}
DUI.Gradients = Gradients

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

Gradients.ORIENTATIONS = { VERTICAL = "Vertical (light on top)", HORIZONTAL = "Horizontal (light at the full end)" }
Gradients.ORIENTATION_ORDER = { "HORIZONTAL", "VERTICAL" }

-- The options page's sections, in order.
Gradients.GROUPS = {
    { id = "class", label = "Classes" },
    { id = "reaction", label = "Others" },
    { id = "power", label = "Power" },
    { id = "cast", label = "Casts" },
    { id = "threat", label = "Threat",
      desc = "Used when Nameplates > Threat > Threat color style is Two-color gradient." },
    { id = "swing", label = "Swing timers" },
    { id = "combo", label = "Combo points",
      desc = "Used when Unit Frames > Extras > Combo points > Colors is a gradient: All points fills every pip with one pair, Point 1 to 5 give each pip its own." },
    { id = "timer", label = "Timers" },
    { id = "reputation", label = "Reputation" },
}

local defs, order = {}, {}

-- def: { group, label, lo = { r, g, b }, hi = { r, g, b } }
function Gradients.Register(key, def)
    if not defs[key] then order[#order + 1] = key end
    defs[key] = def
    DUI.Fire("GradientsRegistered", key)
end

function Gradients.Has(key) return defs[key] ~= nil end

-- A group's keys in registration order.
function Gradients.Keys(group)
    local out = {}
    for _, key in ipairs(order) do
        if defs[key].group == group then out[#out + 1] = key end
    end
    return out
end

function Gradients.Label(key) return defs[key] and defs[key].label or key end

local R = Gradients.Register
R("WARRIOR",     { group = "class", label = "Warrior",      lo = { 0.35, 0.16, 0.08 }, hi = { 0.90, 0.70, 0.45 } })
R("PALADIN",     { group = "class", label = "Paladin",      lo = { 0.60, 0.12, 0.35 }, hi = { 1.00, 0.72, 0.85 } })
R("HUNTER",      { group = "class", label = "Hunter",       lo = { 0.22, 0.38, 0.10 }, hi = { 0.75, 1.00, 0.45 } })
R("ROGUE",       { group = "class", label = "Rogue",        lo = { 0.70, 0.40, 0.00 }, hi = { 1.00, 0.95, 0.45 } })
R("PRIEST",      { group = "class", label = "Priest",       lo = { 0.45, 0.45, 0.50 }, hi = { 0.98, 0.98, 1.00 } })
R("SHAMAN",      { group = "class", label = "Shaman",       lo = { 0.00, 0.12, 0.40 }, hi = { 0.25, 0.65, 1.00 } })
R("MAGE",        { group = "class", label = "Mage",         lo = { 0.02, 0.22, 0.50 }, hi = { 0.60, 0.92, 1.00 } })
R("WARLOCK",     { group = "class", label = "Warlock",      lo = { 0.22, 0.14, 0.42 }, hi = { 0.78, 0.55, 0.95 } })
R("DRUID",       { group = "class", label = "Druid",        lo = { 0.55, 0.10, 0.00 }, hi = { 1.00, 0.70, 0.20 } })
R("DEATHKNIGHT", { group = "class", label = "Death Knight", lo = { 0.35, 0.03, 0.08 }, hi = { 1.00, 0.30, 0.35 } })
R("DEMONHUNTER", { group = "class", label = "Demon Hunter", lo = { 0.22, 0.06, 0.40 }, hi = { 0.82, 0.30, 1.00 } })
R("MONK",        { group = "class", label = "Monk",         lo = { 0.00, 0.35, 0.25 }, hi = { 0.35, 1.00, 0.70 } })
R("EVOKER",      { group = "class", label = "Evoker",       lo = { 0.08, 0.28, 0.40 }, hi = { 0.35, 0.85, 0.75 } })
R("FRIENDLY",    { group = "reaction", label = "Friendly",  lo = { 0.10, 0.40, 0.12 }, hi = { 0.55, 0.95, 0.45 } })
R("NEUTRAL",     { group = "reaction", label = "Neutral",   lo = { 0.65, 0.42, 0.00 }, hi = { 1.00, 0.92, 0.40 } })
R("HOSTILE",     { group = "reaction", label = "Hostile",   lo = { 0.42, 0.04, 0.04 }, hi = { 1.00, 0.35, 0.28 } })
R("TAPPED",      { group = "reaction", label = "Tapped",    lo = { 0.30, 0.30, 0.30 }, hi = { 0.60, 0.60, 0.60 } })
R("FALLBACK",    { group = "reaction", label = "Unknown",   lo = { 0.25, 0.28, 0.35 }, hi = { 0.55, 0.60, 0.70 } })
R("MANA",        { group = "power", label = "Mana",         lo = { 0.14, 0.10, 0.55 }, hi = { 0.55, 0.55, 1.00 } })
R("RAGE",        { group = "power", label = "Rage",         lo = { 0.45, 0.02, 0.02 }, hi = { 1.00, 0.35, 0.25 } })
R("ENERGY",      { group = "power", label = "Energy",       lo = { 0.65, 0.50, 0.00 }, hi = { 1.00, 0.95, 0.40 } })
R("FOCUS",       { group = "power", label = "Focus",        lo = { 0.55, 0.25, 0.05 }, hi = { 1.00, 0.70, 0.35 } })
R("CAST",        { group = "cast", label = "Cast",          lo = { 0.55, 0.38, 0.02 }, hi = { 1.00, 0.85, 0.30 } })
R("CHANNEL",     { group = "cast", label = "Channel",       lo = { 0.10, 0.40, 0.20 }, hi = { 0.50, 1.00, 0.60 } })
R("CAST_INTERRUPTED", { group = "cast", label = "Interrupted", lo = { 0.32, 0.05, 0.04 }, hi = { 0.85, 0.30, 0.25 } })
R("CAST_LOCKED", { group = "cast", label = "Can't interrupt", lo = { 0.22, 0.20, 0.19 }, hi = { 0.72, 0.68, 0.62 } })
R("THREAT_ON",   { group = "threat", label = "Attacking you",     lo = { 0.46, 0.07, 0.06 }, hi = { 0.95, 0.28, 0.24 } })
R("THREAT_WARN", { group = "threat", label = "About to switch",   lo = { 0.55, 0.27, 0.04 }, hi = { 1.00, 0.66, 0.22 } })
R("THREAT_LOST", { group = "threat", label = "Not attacking you", lo = { 0.60, 0.46, 0.06 }, hi = { 1.00, 0.90, 0.38 } })
R("SWING_MAIN",  { group = "swing", label = "Main hand",    lo = { 0.45, 0.30, 0.05 }, hi = { 1.00, 0.80, 0.35 } })
R("SWING_OFF",   { group = "swing", label = "Off hand",     lo = { 0.30, 0.24, 0.14 }, hi = { 0.85, 0.78, 0.62 } })
R("SWING_RANGED",{ group = "swing", label = "Ranged",       lo = { 0.15, 0.35, 0.15 }, hi = { 0.60, 0.95, 0.45 } })
R("SWING_QUEUED",{ group = "swing", label = "Attack queued", lo = { 0.45, 0.12, 0.06 }, hi = { 1.00, 0.60, 0.42 } })
R("COMBO",       { group = "combo", label = "All points",   lo = { 0.55, 0.38, 0.02 }, hi = { 1.00, 0.85, 0.30 } })
-- One pair per pip (COMBO_<n>), warming from pale gold to red.
R("COMBO_1",     { group = "combo", label = "Point 1",      lo = { 0.55, 0.45, 0.08 }, hi = { 1.00, 0.95, 0.55 } })
R("COMBO_2",     { group = "combo", label = "Point 2",      lo = { 0.58, 0.40, 0.02 }, hi = { 1.00, 0.85, 0.30 } })
R("COMBO_3",     { group = "combo", label = "Point 3",      lo = { 0.60, 0.30, 0.02 }, hi = { 1.00, 0.68, 0.20 } })
R("COMBO_4",     { group = "combo", label = "Point 4",      lo = { 0.58, 0.18, 0.02 }, hi = { 1.00, 0.50, 0.16 } })
R("COMBO_5",     { group = "combo", label = "Point 5",      lo = { 0.50, 0.05, 0.04 }, hi = { 1.00, 0.30, 0.22 } })
-- The breath bar and other mirror timers (TIMER_<the game's timer name>).
R("TIMER_BREATH",     { group = "timer", label = "Breath",       lo = { 0.02, 0.22, 0.55 }, hi = { 0.45, 0.80, 1.00 } })
R("TIMER_EXHAUSTION", { group = "timer", label = "Fatigue",      lo = { 0.55, 0.25, 0.02 }, hi = { 1.00, 0.70, 0.25 } })
R("TIMER_FEIGNDEATH", { group = "timer", label = "Feign death",  lo = { 0.55, 0.42, 0.02 }, hi = { 1.00, 0.90, 0.40 } })
R("TIMER_DEATH",      { group = "timer", label = "Release",      lo = { 0.30, 0.30, 0.34 }, hi = { 0.78, 0.80, 0.86 } })
-- Reputation on the experience bar, one per standing (REP_<reaction>, 1 = Hated).
R("REP_1",       { group = "reputation", label = "Hated",      lo = { 0.28, 0.02, 0.04 }, hi = { 0.80, 0.12, 0.16 } })
R("REP_2",       { group = "reputation", label = "Hostile",    lo = { 0.45, 0.06, 0.04 }, hi = { 1.00, 0.32, 0.22 } })
R("REP_3",       { group = "reputation", label = "Unfriendly", lo = { 0.50, 0.18, 0.02 }, hi = { 1.00, 0.58, 0.22 } })
R("REP_4",       { group = "reputation", label = "Neutral",    lo = { 0.60, 0.45, 0.00 }, hi = { 1.00, 0.90, 0.35 } })
R("REP_5",       { group = "reputation", label = "Friendly",   lo = { 0.10, 0.38, 0.10 }, hi = { 0.50, 0.92, 0.40 } })
R("REP_6",       { group = "reputation", label = "Honored",    lo = { 0.00, 0.35, 0.28 }, hi = { 0.30, 0.95, 0.70 } })
R("REP_7",       { group = "reputation", label = "Revered",    lo = { 0.02, 0.25, 0.50 }, hi = { 0.40, 0.80, 1.00 } })
R("REP_8",       { group = "reputation", label = "Exalted",    lo = { 0.30, 0.10, 0.50 }, hi = { 0.85, 0.55, 1.00 } })

local function settings()
    local g = DUI.DB.General().gradients
    return type(g) == "table" and g or {}
end

-- General > Gradients off: every pair paints flat at its middle, the
-- gradient accent becomes one color (Style.AccentSweep), and the Daylight bar
-- sweep its purple (Style.SetBarGradient). The pairs themselves (RGB, the
-- option rows) are untouched, so turning it back on loses nothing.
-- Also true under the Classic look, which uses the game's plain bars unless
-- the player switched Gradient bars on. Off() is the master switch alone.
function Gradients.Off() return settings().off == true end
function Gradients.Flat()
    if Gradients.Off() then return true end
    local g = DUI.DB.General()
    return g.look == "classic" and g.lookGradients ~= true
end

local function rgbOf(c, fallback)
    if type(c) == "table" and type(c[1]) == "number" then return c end
    return fallback
end

-- Palettes: a whole set of pairs picked at once. The player's own changes sit
-- on top of the palette, and a reset goes back to the palette's pair.
-- def: { label, set = { KEY = { lo, hi } }?, derive = function(key, def) -> lo, hi }?
-- Keys the palette doesn't cover keep their shipped pair.
local palettes = {}
Gradients.PALETTE_ORDER = {}

function Gradients.RegisterPalette(id, def)
    if not palettes[id] then Gradients.PALETTE_ORDER[#Gradients.PALETTE_ORDER + 1] = id end
    palettes[id] = def
    DUI.Fire("GradientsRegistered", id)
end

-- { id = label } for the options dropdown.
function Gradients.PaletteValues()
    local out = {}
    for id, p in pairs(palettes) do out[id] = p.label end
    return out
end

function Gradients.Palette()
    local id = settings().palette
    return palettes[id] and id or "daylight"
end

local function mix(c, to, amount)
    return { c[1] + (to[1] - c[1]) * amount, c[2] + (to[2] - c[2]) * amount, c[3] + (to[3] - c[3]) * amount }
end
local BLACK, GREY, WHITE = { 0, 0, 0 }, { 0.5, 0.5, 0.5 }, { 1, 1, 1 }

Gradients.RegisterPalette("daylight", { label = "Daylight" })
Gradients.RegisterPalette("classcolor", { label = "Game class colors",
    -- Bolder casts and swings that sit well beside the game's class colors.
    set = {
        CAST             = { lo = { 0.60, 0.30, 0.00 }, hi = { 1.00, 0.80, 0.10 } },
        CHANNEL          = { lo = { 0.00, 0.40, 0.45 }, hi = { 0.30, 0.95, 0.90 } },
        CAST_INTERRUPTED = { lo = { 0.50, 0.00, 0.00 }, hi = { 1.00, 0.20, 0.15 } },
        CAST_LOCKED      = { lo = { 0.25, 0.25, 0.27 }, hi = { 0.78, 0.78, 0.82 } },
        SWING_MAIN       = { lo = { 0.55, 0.35, 0.00 }, hi = { 1.00, 0.85, 0.25 } },
        SWING_OFF        = { lo = { 0.30, 0.25, 0.55 }, hi = { 0.70, 0.65, 1.00 } },
        SWING_RANGED     = { lo = { 0.10, 0.45, 0.10 }, hi = { 0.45, 1.00, 0.35 } },
        SWING_QUEUED     = { lo = { 0.60, 0.10, 0.00 }, hi = { 1.00, 0.50, 0.15 } },
    },
    derive = function(key, def)
        if def.group ~= "class" then return nil end
        local r, g, b = Style.RawClassColor(key)
        if not r then return nil end
        local rgb = { r, g, b }
        return mix(rgb, BLACK, 0.55), mix(rgb, WHITE, 0.25)
    end })
Gradients.RegisterPalette("soft", { label = "Soft",
    derive = function(_, def) return mix(def.lo, GREY, 0.3), mix(def.hi, WHITE, 0.35) end })

-- The pair under the player's changes: the palette's, else the shipped one.
local function base(key)
    if not defs[key] then key = "FALLBACK" end
    local def = defs[key]
    local p = palettes[Gradients.Palette()]
    local own = p and p.set and p.set[key]
    if type(own) == "table" then return own.lo, own.hi end
    if p and p.derive then
        local lo, hi = p.derive(key, def)
        if lo then return lo, hi end
    end
    return def.lo, def.hi
end

-- The pair after the player's changes, unsoftened, as lo, hi { r, g, b }
-- (shared tables, don't modify). Cached per key until a General setting, the
-- style or a registration changes (a profile switch replaces the settings
-- table). The class gradient accent asks for it on every Style.Accent().
local rgbCache, rgbGen = {}, nil

function Gradients.RGB(key)
    if not defs[key] then key = "FALLBACK" end
    local gen = DUI.DB.General()
    if gen ~= rgbGen then rgbCache, rgbGen = {}, gen end
    local e = rgbCache[key]
    if e then return e[1], e[2] end
    local lo, hi = base(key)
    local mine = settings().colors
    mine = type(mine) == "table" and mine[key]
    if type(mine) == "table" then lo, hi = rgbOf(mine.lo, lo), rgbOf(mine.hi, hi) end
    rgbCache[key] = { lo, hi }
    return lo, hi
end

-- The palette's pair as { lo = { r, g, b }, hi = { r, g, b } } (copies).
function Gradients.Default(key)
    local lo, hi = base(key)
    return { lo = { lo[1], lo[2], lo[3] }, hi = { hi[1], hi[2], hi[3] } }
end

local function same(a, b)
    for i = 1, 3 do
        if type(a[i]) ~= "number" or math.abs(a[i] - b[i]) > 1e-3 then return false end
    end
    return true
end

-- Saves a pair. Only an end that differs from the palette's is stored, so a
-- pair set back to the palette's leaves nothing behind.
function Gradients.SetPair(key, lo, hi)
    if not defs[key] then return end
    local dlo, dhi = base(key)
    local entry = {}
    if type(lo) == "table" and not same(lo, dlo) then entry.lo = { lo[1], lo[2], lo[3] } end
    if type(hi) == "table" and not same(hi, dhi) then entry.hi = { hi[1], hi[2], hi[3] } end
    DUI:Set("general", "gradients.colors." .. key, next(entry) and entry or nil)
end

-- Resets every pair to its default (orientation and invert are kept).
function Gradients.ResetAll()
    DUI:Set("general", "gradients.colors", {})
end

function Gradients.AnyChanged()
    local mine = settings().colors
    return type(mine) == "table" and next(mine) ~= nil
end

-- Built pairs, cached until a setting or the style changes (a profile switch
-- replaces the settings table, so that's compared too). Plain value compares
-- and no key strings, since this runs on every paint of every bar.
local cache, cacheGen, cacheSoft, cacheBright = {}, nil, nil, nil

function Gradients.Invalidate() cache, cacheGen, rgbCache, rgbGen = {}, nil, {}, nil end
DUI.On("RepaintCore", Gradients.Invalidate)
DUI.On("GradientsRegistered", Gradients.Invalidate)
DUI.On("SettingChanged", function(scope) if scope == "general" then Gradients.Invalidate() end end)

local function built(key)
    if not defs[key] then key = "FALLBACK" end
    local gen = DUI.DB.General()
    if gen ~= cacheGen or gen.softness ~= cacheSoft or gen.brightness ~= cacheBright then
        cache, cacheGen, cacheSoft, cacheBright = {}, gen, gen.softness, gen.brightness
    end
    local e = cache[key]
    if e then return e end
    local lo, hi = Gradients.RGB(key)
    local lr, lg, lb = Style.Soften(lo[1], lo[2], lo[3])
    local hr, hg, hb = Style.Soften(hi[1], hi[2], hi[3])
    local mid = { (lr + hr) / 2, (lg + hg) / 2, (lb + hb) / 2 }
    if Gradients.Flat() then lr, lg, lb, hr, hg, hb = mid[1], mid[2], mid[3], mid[1], mid[2], mid[3] end
    e = { lo = { lr, lg, lb }, hi = { hr, hg, hb }, mid = mid }
    if CreateColor then
        e.loColor, e.hiColor = CreateColor(lr, lg, lb, 1), CreateColor(hr, hg, hb, 1)
    end
    cache[key] = e
    return e
end

-- The pair softened, in painting order (invert swaps it, flip swaps it
-- again). Returns two colors.
function Gradients.Colors(key, flip)
    local e = built(key)
    if (settings().invert == true) ~= (flip == true) then return e.hiColor, e.loColor end
    return e.loColor, e.hiColor
end

-- Same as two { r, g, b } tables (for the options page's preview).
function Gradients.PaintRGB(key)
    local e = built(key)
    if settings().invert then return e.hi, e.lo end
    return e.lo, e.hi
end

-- A pair's options row (General > Gradients, and next to the bars that use
-- it), so the same pair shows wherever it appears. label is the row's name.
function Gradients.Item(key, label)
    return { type = "gradient", label = label or Gradients.Label(key),
        desc = "Dark end, then light end. The bar next to them is a preview.",
        get = function()
            local lo, hi = Gradients.RGB(key)
            return { lo = lo, hi = hi }
        end,
        set = function(v) Gradients.SetPair(key, v.lo, v.hi) end,
        default = function() return Gradients.Default(key) end,
        preview = function() return Gradients.PaintRGB(key) end }
end

-- The pair's middle, softened: r, g, b.
function Gradients.Mid(key)
    local m = built(key).mid
    return m[1], m[2], m[3]
end

-- Text in the pair, dark to light from left to right (invert swaps), as a
-- string of per-letter color codes. Draw it with a white font color. Anything
-- that isn't a plain string (a secret name) is returned unchanged.
function Gradients.Text(key, text)
    if isSecret(text) or type(text) ~= "string" or text == "" then return text end
    local e = built(key)
    local lo, hi = e.lo, e.hi
    if settings().invert then lo, hi = hi, lo end
    local chars = {}
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    local n, out = #chars, {}
    for i, ch in ipairs(chars) do
        local t = n > 1 and (i - 1) / (n - 1) or 0.5
        out[i] = string.format("|cff%02x%02x%02x%s|r",
            math.floor((lo[1] + (hi[1] - lo[1]) * t) * 255 + 0.5),
            math.floor((lo[2] + (hi[2] - lo[2]) * t) * 255 + 0.5),
            math.floor((lo[3] + (hi[3] - lo[3]) * t) * 255 + 0.5), ch)
    end
    return table.concat(out)
end

function Gradients.Orientation()
    local o = settings().orientation
    return Gradients.ORIENTATIONS[o] and o or "HORIZONTAL"
end

-- The pair for a unit: its class for players, else its reaction (or tapped).
-- Anything secret or unknown gets the fallback.
function Gradients.KeyFor(unit)
    if unit == nil then return "FALLBACK" end
    local isPlayer = UnitIsPlayer(unit)
    if isSecret(isPlayer) then return "FALLBACK" end
    if isPlayer then
        local _, token = UnitClass(unit)
        if isSecret(token) or type(token) ~= "string" or not defs[token] then return "FALLBACK" end
        return token
    end
    local tapped = UnitIsTapDenied and UnitIsTapDenied(unit)
    if not isSecret(tapped) and tapped == true then return "TAPPED" end
    local reaction = UnitReaction(unit, "player")
    if isSecret(reaction) or type(reaction) ~= "number" then return "FALLBACK" end
    if reaction <= 3 then return "HOSTILE" end
    if reaction == 4 then return "NEUTRAL" end
    return "FRIENDLY"
end

-- Hidden classes. In battlegrounds the game hides an enemy player's class (a
-- secret), so it can't be looked up, but these can still color by it without
-- reading it. Bars get a layer per class over the fill, each in its class
-- colors. Each layer's sheet has only that class's cell filled, and
-- SetSpriteSheetCell accepts the secret class id, so only the unit's own
-- class shows (sheets from make_class_cells.py). Text uses the client's class
-- color as secret numbers.
Gradients.CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
Gradients.CLASS_SHEET = DUI.MEDIA .. "classcell-" -- .. id .. ".png", a 4 x 4 sheet

-- A player whose class the game hides: returns its (secret) class id, else
-- nil. Never test the id itself.
function Gradients.HiddenClassID(unit)
    if unit == nil or type(UnitClassBase) ~= "function" then return nil end
    local isPlayer = UnitIsPlayer(unit)
    if isSecret(isPlayer) or isPlayer ~= true then return nil end
    local ok, _, id = pcall(UnitClassBase, unit)
    if ok and isSecret(id) then return id end
    return nil
end

-- That player's class color as the client's secret numbers (for any setter
-- that accepts secrets: text, bar and texture colors), else nil. It's the
-- plain class color, since secrets can't be softened.
function Gradients.HiddenClassColor(unit)
    if not Gradients.HiddenClassID(unit) or not (C_ClassColor and C_ClassColor.GetClassColor) then return nil end
    local ok, token = pcall(UnitClassBase, unit)
    if not ok then return nil end
    local got, c = pcall(C_ClassColor.GetClassColor, token)
    if got and type(c) == "table" then return c.r, c.g, c.b end
    return nil
end

-- The class layers over bar's fill (they grow with it and share its angled
-- edge). each(tex) does extra setup per layer, such as clipping.
function Gradients.ClassLayers(bar, each)
    local layers = {}
    for token, id in pairs(Gradients.CLASS_IDS) do
        local tex = bar:CreateTexture(nil, "ARTWORK", nil, 1)
        tex:SetTexture(Gradients.CLASS_SHEET .. id .. ".png")
        Style.FollowFill(bar, tex)
        if each then each(tex) end
        tex:Hide()
        layers[token] = tex
    end
    return layers
end

-- Shows the layers for a secret class id in mode "class" (flat) or
-- "classGradient" (flip runs the pair the other way). A nil mode hides them.
function Gradients.PaintClassLayers(layers, id, mode, flip)
    for token, tex in pairs(layers) do
        local shown = false
        if mode then
            if mode == "classGradient" then
                tex:SetVertexColor(1, 1, 1, 1)
                local lo, hi = Gradients.Colors(token, flip)
                if lo then tex:SetGradient(Gradients.Orientation(), lo, hi) end
            else
                tex:SetVertexColor(Style.ClassColor(token))
            end
            shown = pcall(tex.SetSpriteSheetCell, tex, id, 4, 4)
        end
        tex:SetShown(shown)
    end
end

-- The pair for a power type (a token like "RAGE"). A secret or unknown type
-- gets mana's, same as the plain power colors.
function Gradients.PowerKey(token)
    if isSecret(token) or type(token) ~= "string" then return "MANA" end
    local def = defs[token]
    return def and def.group == "power" and token or "MANA"
end

-- Fills a status bar with a pair. paintBack(bar, r, g, b) first colors the
-- bar (and its empty part) at the pair's middle. The gradient goes on last
-- because any plain color set after it clears it. With mirror, a bar on the
-- other side (the target) runs the other way so the two face each other;
-- only horizontal gradients mirror.
function Gradients.Paint(bar, key, paintBack, mirror)
    (paintBack or Style.SetBarColor)(bar, Gradients.Mid(key))
    bar:SetStatusBarColor(1, 1, 1, 1)
    local tex = bar:GetStatusBarTexture()
    local lo, hi = Gradients.Colors(key, mirror and Gradients.Orientation() == "HORIZONTAL")
    if type(tex) == "table" and tex.SetGradient and lo then
        tex:SetGradient(Gradients.Orientation(), lo, hi)
    end
end

-- Same, with the pair chosen for the unit.
function Gradients.PaintUnit(bar, unit, paintBack, mirror)
    Gradients.Paint(bar, Gradients.KeyFor(unit), paintBack, mirror)
end

-- A pair built from one color { r, g, b }: a darker shade, then the color
-- itself. Returns unsoftened copies lo, hi.
Gradients.FROM_DIM = 0.55 -- the dark end, as a fraction of the color
function Gradients.PairFrom(rgb)
    if Gradients.Flat() then return { rgb[1], rgb[2], rgb[3] }, { rgb[1], rgb[2], rgb[3] } end
    local k = Gradients.FROM_DIM
    return { rgb[1] * k, rgb[2] * k, rgb[3] * k }, { rgb[1], rgb[2], rgb[3] }
end

-- A raw pair's middle, softened: r, g, b.
function Gradients.MidOf(lo, hi)
    local lr, lg, lb = Style.Soften(lo[1], lo[2], lo[3])
    local hr, hg, hb = Style.Soften(hi[1], hi[2], hi[3])
    return (lr + hr) / 2, (lg + hg) / 2, (lb + hb) / 2
end

-- A raw pair as it paints: softened, in painting order (invert swaps it), as
-- two { r, g, b }.
function Gradients.PaintRGBOf(lo, hi)
    local lr, lg, lb = Style.Soften(lo[1], lo[2], lo[3])
    local hr, hg, hb = Style.Soften(hi[1], hi[2], hi[3])
    if Gradients.Flat() then
        local m = { (lr + hr) / 2, (lg + hg) / 2, (lb + hb) / 2 }
        return m, m
    end
    local a, b = { lr, lg, lb }, { hr, hg, hb }
    if settings().invert == true then return b, a end
    return a, b
end

-- Paints a plain white texture (an aura's edge, a swatch) with a raw pair.
-- White first, since a plain color set after the gradient would clear it.
-- alpha is optional, default 1.
function Gradients.PaintPair(tex, lo, hi, alpha)
    if type(tex) ~= "table" then return end
    local a, b = Gradients.PaintRGBOf(lo, hi)
    local al = type(alpha) == "number" and alpha or 1
    if not tex.SetGradient or not CreateColor then
        tex:SetVertexColor((a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2, al)
        return
    end
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetGradient(Gradients.Orientation(), CreateColor(a[1], a[2], a[3], al), CreateColor(b[1], b[2], b[3], al))
end

-- Fills a status bar with a gradient built from one color { r, g, b }.
function Gradients.PaintFrom(bar, rgb)
    local lo, hi = Gradients.PairFrom(rgb)
    Style.SetBarColor(bar, Gradients.MidOf(lo, hi))
    bar:SetStatusBarColor(1, 1, 1, 1)
    Gradients.PaintPair(bar:GetStatusBarTexture(), lo, hi)
end

-- Combo points (the unit frames' and nameplates' pips). Each pip's color
-- comes from the unit frames' combo settings (cfg; nil uses the defaults,
-- e.g. with unit frames off). pips: { { bar = StatusBar, full = StatusBar? } }.
-- colorMode: color (one color), blend (color to fullColor along the row),
-- class, gradient (the COMBO pair on every pip), points (COMBO_<n> each).
-- fullRed: the last pip fills in fullColor. fullAll: every pip's overlay
-- (pip.full, spanning the last point) shows it, so the whole row changes
-- color at max points. empty: brightness of the unfilled part.
Gradients.COMBO_COLOR = { 1.0, 0.82, 0.25 }
Gradients.COMBO_FULL = { 0.95, 0.22, 0.2 }
function Gradients.PaintCombo(pips, cfg)
    cfg = type(cfg) == "table" and cfg or {}
    local mode = cfg.colorMode or "color"
    local col = rgbOf(cfg.color, Gradients.COMBO_COLOR)
    local full = rgbOf(cfg.fullColor, Gradients.COMBO_FULL)
    local dim = tonumber(cfg.empty) or Style.BAR_BACK_DIM
    local red = cfg.fullRed ~= false
    local fr, fg, fb = Style.Soften(full[1], full[2], full[3])
    local n = #pips
    for i, pip in ipairs(pips) do
        local bar = pip.bar
        Style.SetBarGradient(bar, false)
        local key, r, g, b
        if mode == "gradient" then
            key = "COMBO"
        elseif mode == "points" then
            key = defs["COMBO_" .. i] and ("COMBO_" .. i) or "COMBO"
        elseif mode == "class" then
            local _, token = UnitClass("player")
            r, g, b = Style.ClassColor(token)
        elseif mode == "blend" then
            local c = mix(col, full, n > 1 and (i - 1) / (n - 1) or 0)
            r, g, b = Style.Soften(c[1], c[2], c[3])
        else
            r, g, b = Style.Soften(col[1], col[2], col[3])
        end
        local pair
        if key then
            Gradients.Paint(bar, key)
            r, g, b = Gradients.Mid(key)
            pair = { Gradients.Colors(key) }
        else
            Style.SetBarColor(bar, r, g, b)
        end
        -- What the fill shows, so FlashCombo can return to it.
        pip.color, pip.pair = { r, g, b }, pair
        if i == n and red then
            bar:SetStatusBarColor(fr, fg, fb, 1)
            pip.color, pip.pair = { fr, fg, fb }, nil
        end
        local back = Style.BarBack(bar)
        if back then back:SetVertexColor(r * dim, g * dim, b * dim, Style.BAR_BACK_ALPHA) end
        if pip.full then
            pip.full:SetStatusBarColor(fr, fg, fb, 1)
            pip.full:SetShown(red and cfg.fullAll == true)
        end
    end
end

-- "Spark": a gained point snaps its pip's fill to white, holds briefly, then
-- fades back to the color PaintCombo gave it (a repaint mid-flash is picked
-- up by the next step), while a soft glow bursts around the pip. Only a color
-- lerp and a fading glow, never a scale. Nothing with motion off.
Gradients.COMBO_FLASH = 1 -- how close to white it starts
Gradients.COMBO_SPARK = 0.55 -- total flash time in seconds (the first ~fifth is held)
local function comboTint(pip, v)
    local c, pair = pip.color, pip.pair
    if not c then return end
    local function lift(x) return x + (1 - x) * v end
    local tex = pip.bar:GetStatusBarTexture()
    if pair and tex and tex.SetGradient and CreateColor then
        local lo, hi = pair[1], pair[2]
        pip.bar:SetStatusBarColor(1, 1, 1, 1)
        tex:SetGradient(Gradients.Orientation(), CreateColor(lift(lo.r), lift(lo.g), lift(lo.b), 1),
            CreateColor(lift(hi.r), lift(hi.g), lift(hi.b), 1))
    else
        pip.bar:SetStatusBarColor(lift(c[1]), lift(c[2]), lift(c[3]), 1)
    end
end

-- Fades a glow out over dur (past the first half of Tween's eased value it's
-- in the tail).
local function fadeGlow(tex, peak, dur)
    tex:SetAlpha(peak)
    tex:Show()
    DUI.Motion.Tween(tex, 0, 1, dur, function(e) tex:SetAlpha(peak * (1 - e)) end, function() tex:Hide() end)
end

function Gradients.FlashCombo(pip)
    local M = DUI.Motion
    if not (pip and pip.color and M.On()) then return end
    -- Tween eases out, so its value passes 0.5 about a fifth of the way in.
    -- Holding white until then is the beat, and the rest is a slow fade.
    M.Tween(pip, 0, 1, Gradients.COMBO_SPARK, function(e)
        comboTint(pip, Gradients.COMBO_FLASH * (e < 0.5 and 1 or (1 - e) / 0.5))
    end)
    if pip.burst then fadeGlow(pip.burst, 1, Gradients.COMBO_SPARK) end
end

-- The lights on a combo row, on a frame over the pips, created with the row
-- and hidden until PopCombo runs them (additive glow, no masks): a burst per
-- pip, the band that sweeps across at max points (Motion.Sweep fades its
-- ends), and a glow over the whole row.
Gradients.COMBO_SWEEP = { width = 80, dur = 0.55, alpha = 1, color = { 1, 0.95, 0.85 } }
Gradients.COMBO_BURST = { 1, 0.82, 0.5 } -- the glow around a gained pip
Gradients.COMBO_ROWGLOW = 0.7 -- the row glow at max points, seconds
local function glow(top, color)
    local t = top:CreateTexture(nil, "OVERLAY", nil, 6)
    t:SetTexture(DUI.MEDIA .. "glow.png")
    t:SetBlendMode("ADD")
    t:SetVertexColor(color[1], color[2], color[3])
    t:Hide()
    return t
end

function Gradients.ComboSweep(row)
    local top = CreateFrame("Frame", nil, row)
    top:SetAllPoints(row)
    local last = row.pips[#row.pips]
    top:SetFrameLevel((last.full or last.bar):GetFrameLevel() + 1)
    for _, pip in ipairs(row.pips) do
        pip.burst = glow(top, Gradients.COMBO_BURST)
        pip.burst:SetPoint("CENTER", pip, "CENTER")
    end
    row.glow = glow(top, Gradients.COMBO_BURST)
    row.glow:SetPoint("CENTER", row, "CENTER")
    local t = glow(top, Gradients.COMBO_SWEEP.color)
    t:SetDrawLayer("OVERLAY", 7)
    row.sweep = t
    row.lights = top
end


-- Whether a power event left a combo row's count unchanged (row.last, the
-- plain count PopCombo saw). A finisher's spend arrives on the energy event
-- (in game there's no COMBO_POINTS event and the points sat at five), and the
-- game's own combo frame (Camelot/ComboFrame.lua) redraws on every power
-- event. So every event reads the count and only a change redraws (energy
-- ticks many times a second). Secret, or nothing seen yet, counts as changed.
function Gradients.ComboSame(row, powerType)
    if powerType == "COMBO_POINTS" or isSecret(powerType) then return false end
    if type(row.last) ~= "number" or not GetComboPoints then return false end
    local n = GetComboPoints("player", "target")
    return not isSecret(n) and n == row.last
end

-- A combo row's count (row.pips, row.sweep). A plain count that went up since
-- the last one on the same target flashes each new pip, and reaching max
-- points sweeps light across the row. A secret count, the first look, and a
-- new target (fresh) just record it.
function Gradients.PopCombo(row, n, fresh)
    local last = row.last
    if isSecret(n) or type(n) ~= "number" then row.last = nil; return end
    row.last = n
    if fresh or last == nil then return end
    local max = #row.pips
    if n <= last then return end
    -- Above the pips even if the row was re-leveled since (a plate's row is, on
    -- every target).
    local top = row.pips[max]
    if row.lights then row.lights:SetFrameLevel((top.full or top.bar):GetFrameLevel() + 1) end
    for i = last + 1, math.min(n, max) do
        local pip = row.pips[i]
        -- Sized now, since the pips' size follows the settings.
        if pip.burst then pip.burst:SetSize((pip:GetWidth() or 0) * 2, (pip:GetHeight() or 0) * 3.2) end
        Gradients.FlashCombo(pip)
    end
    if n >= max and row.sweep and DUI.Motion.On() then
        local h = row:GetHeight() or 0
        row.sweep:SetHeight(h * 3)
        DUI.Motion.Sweep(row.sweep, row, Gradients.COMBO_SWEEP)
        if row.glow then
            row.glow:SetSize((row:GetWidth() or 0) + h * 2, h * 4)
            fadeGlow(row.glow, 0.85, Gradients.COMBO_ROWGLOW)
        end
    end
end
