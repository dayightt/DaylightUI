-- The one place that decides how DaylightUI looks. Modules ask for shells,
-- bars, text and colors here and never pick textures or colors themselves,
-- so a change to the look reaches everything at once.

local _, DUI = ...

local Style = {}
DUI.Style = Style

local WHITE = "Interface\\Buttons\\WHITE8x8"
local CORNER = DUI.MEDIA .. "corner.png"
local SHADOW = DUI.MEDIA .. "shadow.png"
-- Round shadow corners with the solid core at 0.3 .. 0.9 of the piece. The
-- one nearest curve / (curve + shadow) fades exactly like the edges (a fixed
-- core left a darker blob past a small curve on action buttons).
local SHADOW_ROUND = {}
for k = 3, 9 do SHADOW_ROUND[k] = DUI.MEDIA .. "shadow-round-" .. k .. ".png" end
local function shadowRound(R, S)
    local k = math.floor(10 * R / (R + S) + 0.5)
    return SHADOW_ROUND[math.max(3, math.min(9, k))]
end
local FILLET = DUI.MEDIA .. "fillet.png"
local SLANT_MASK = { right = DUI.MEDIA .. "mask-slant-r.png", left = DUI.MEDIA .. "mask-slant-l.png" }
-- The other side of the same lines: keeps what lies past a line toward the edge.
local TRAIL_MASK = { right = DUI.MEDIA .. "mask-trail-r.png", left = DUI.MEDIA .. "mask-trail-l.png" }
-- Crisp, square-tipped versions for a cut stretched past the 64px masks (a big
-- frame, or a column of frames sharing one line). Stretched, the soft edge
-- smears and borders stacked at a join look darker than the cut.
local SLANT_SHARP = { right = DUI.MEDIA .. "mask-slant-r-sharp.png", left = DUI.MEDIA .. "mask-slant-l-sharp.png" }
local TRAIL_SHARP = { right = DUI.MEDIA .. "mask-trail-r-sharp.png", left = DUI.MEDIA .. "mask-trail-l-sharp.png" }
local SHARP_PAST = 48 -- mask width (4x the cut) past which the soft edge smears
-- An end leaning under (its bottom corner sticks out, not its top) is the
-- other end's cut turned around, so its masks are the same images swapped:
-- its cut is the other end's trail and vice versa.
local function slantImage(trail, end_, under, sharp)
    local other = end_ == "left" and "right" or "left"
    if under then trail, end_ = not trail, other end
    if trail then return (sharp and TRAIL_SHARP or TRAIL_MASK)[end_] end
    return (sharp and SLANT_SHARP or SLANT_MASK)[end_]
end
-- An end leans under when the slant's under is that end or "both" (a
-- trapezoid wider at the bottom).
local function leans(under, end_) return under ~= nil and (under == end_ or under == "both") end
-- Bar textures: a soft-edged fill over a brushed backing texture.
Style.BAR = {
    fill = DUI.MEDIA .. "bar-plain.tga",
    -- Same top-to-bottom shading but none at the ends, for fills that start
    -- partway along another bar (heal prediction).
    seamless = DUI.MEDIA .. "bar-seamless.tga",
    back = DUI.MEDIA .. "bar-back.tga",
}
Style.BAR_BACK_ALPHA = 0.8
Style.BAR_BACK_DIM = 0.4
Style.SEPARATOR_PX = 2
Style.TEXT_SHADOW = { 1, -1, 0.6 } -- x, y offset and alpha of the text drop shadow
-- Every square icon's crop. The game's art has a rim, so 8% is cut off each side.
Style.ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }
function Style.CropIcon(tex)
    local c = Style.ICON_CROP
    tex:SetTexCoord(c[1], c[2], c[3], c[4])
end

-- The client's dispel type keys ("None" is an aura with no type).
Style.DISPEL_KEYS = { "None", "Magic", "Curse", "Disease", "Poison", "Bleed", "Enrage" }

-- Registers tex on a client aura button to be tinted by the aura's dispel
-- type. The client picks it, so a secret type works. Uses our colors on a
-- white square via the enum style and color objects (the plain string form is
-- silently ignored by this client), else the client's own colors.
-- colorOf(key) -> { r, g, b }. opts: helpful (buffs, not debuffs),
-- withoutType (false: nothing for an aura with no type), asset and coords
-- (another texture and its { left, right, top, bottom } crop; the client
-- ignores opacity set on a tinted texture, so a transparent tint must be in
-- the texture itself). Returns "custom", "client" or nil.
--
-- The asset and color maps passed to AddDispelTypeTexture are shared by every
-- button with the same look, since the game's color objects are heavy (each a
-- copy of ColorMixin) and thousands of aura buttons are created at login.
-- source is colorOf(key) or a table of colors (a key without one is left
-- out). like is the key that None uses instead (the halo uses Magic). A shared
-- set is never modified; other colors (a softness change) make a new one.
local dispelSets, softened = {}, {}
Style.DISPEL_SETS = 32 -- how many recent sets are kept; older ones are dropped when a look changes this often
local function sameCoords(a, b)
    if a == b then return true end
    if not (a and b) then return false end
    return a.left == b.left and a.right == b.right and a.top == b.top and a.bottom == b.bottom
end
local function dispelSet(source, asset, coords, like)
    local keys = Style.DISPEL_KEYS
    local n = 0
    for i, key in ipairs(keys) do
        local c
        if type(source) == "function" then c = source(key) else c = source[key] end
        local base = (i - 1) * 3
        if c then
            softened[base + 1], softened[base + 2], softened[base + 3] = Style.Soften(c[1], c[2], c[3])
        else
            softened[base + 1] = false
        end
        n = base + 3
    end
    for _, set in ipairs(dispelSets) do
        if set.asset == asset and set.like == like and sameCoords(set.coords, coords) then
            local same = true
            for i = 1, n do
                if set.rgb[i] ~= softened[i] then same = false break end
            end
            if same then return set.assets, set.colors end
        end
    end
    local set = { asset = asset, like = like, rgb = {}, assets = {}, colors = {},
        coords = coords and { left = coords.left, right = coords.right, top = coords.top, bottom = coords.bottom } }
    for i = 1, n do set.rgb[i] = softened[i] end
    for i, key in ipairs(keys) do
        local base = (i - 1) * 3
        if softened[base + 1] then
            set.assets[key] = { asset = asset, texCoords = set.coords }
            set.colors[key] = CreateColor(softened[base + 1], softened[base + 2], softened[base + 3], 1)
        end
    end
    if like then set.assets.None, set.colors.None = set.assets[like], set.colors[like] end
    table.insert(dispelSets, 1, set)
    dispelSets[Style.DISPEL_SETS + 1] = nil
    return set.assets, set.colors
end

function Style.DispelEdge(btn, tex, colorOf, opts)
    opts = opts or {}
    if not btn.AddDispelTypeTexture then return nil end
    local styles = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    if not styles then return nil end
    local assets, colors = dispelSet(colorOf, opts.asset or WHITE, opts.coords)
    local helpful = opts.helpful == true
    if styles.CustomAsset and pcall(btn.AddDispelTypeTexture, btn, tex, { showWhenHarmful = not helpful,
        showWhenHelpful = helpful, showWithoutDispelType = opts.withoutType ~= false, style = styles.CustomAsset,
        customDispelAssetMap = assets, customDispelColorMap = colors }) then
        return "custom"
    end
    if styles.PreserveAsset and pcall(btn.AddDispelTypeTexture, btn, tex, { showWhenHarmful = not helpful,
        showWhenHelpful = helpful, showWithoutDispelType = opts.withoutType ~= false, style = styles.PreserveAsset }) then
        return "client"
    end
    return nil
end
-- The text size scale for our windows and panels. Pick by what the text is,
-- never a number of your own.
Style.SIZE = {
    tiny = 10, -- counts, badges, keybind text, small tags
    small = 12, -- sub lines, hints, labels, footnotes
    body = 13, -- rows, sentences, buttons, values
    head = 15, -- a card's or section's heading
    title = 18, -- a window's title
}
-- One font everywhere, picked in Appearance. The bundled fonts are all free to
-- share (Media/fonts/FONTS.txt). "Game font" is whatever the client uses, so a
-- player's own font override shows up there without us shipping it.
local FONTS = DUI.MEDIA .. "fonts\\"
Style.FONTS = {
    expressway = { label = "Expressway", file = FONTS .. "ExpresswayFree.ttf" },
    ptsans = { label = "PT Sans Narrow", file = FONTS .. "PTSansNarrow-Bold.ttf" },
    archivo = { label = "Archivo Narrow", file = FONTS .. "ArchivoNarrow-Bold.ttf" },
    barlow = { label = "Barlow Condensed", file = FONTS .. "BarlowCondensed-Medium.ttf" },
    fira = { label = "Fira Sans", file = FONTS .. "FiraSans-Medium.ttf" },
    poppins = { label = "Poppins", file = FONTS .. "Poppins-SemiBold.ttf" },
    lato = { label = "Lato", file = FONTS .. "Lato-Regular.ttf" },
    russo = { label = "Russo One", file = FONTS .. "RussoOne-Regular.ttf" },
    game = { label = "Game font", game = true },
    arialn = { label = "Arial Narrow", file = "Fonts\\ARIALN.TTF" },
}
-- Display fonts (tools/make_fonts.py, licenses in Media/fonts/DISPLAY-FONTS.txt).
-- Made for damage numbers but offered for all text. `display` marks those that
-- are hard to read as body text, so the options window keeps its body on
-- Expressway (Theme.BodyFont).
local DISPLAY = {
    -- comic, chunky
    { "bangers", "Bangers", "Bangers" }, { "luckiest", "Luckiest Guy", "LuckiestGuy" },
    { "titan", "Titan One", "TitanOne" }, { "bowlby", "Bowlby One", "BowlbyOneSC" },
    { "lilita", "Lilita One", "LilitaOne" }, { "coiny", "Coiny", "Coiny" }, { "chewy", "Chewy", "Chewy" },
    -- tall impact
    { "anton", "Anton", "Anton" }, { "bebas", "Bebas Neue", "BebasNeue" },
    { "staatliches", "Staatliches", "Staatliches" }, { "oswald", "Oswald", "Oswald-Bold" },
    { "teko", "Teko", "Teko-SemiBold" }, { "bigshoulders", "Big Shoulders", "BigShoulders-Black" },
    { "passion", "Passion One", "PassionOne" }, { "squada", "Squada One", "SquadaOne" },
    -- tech
    { "blackops", "Black Ops One", "BlackOpsOne", true }, { "audiowide", "Audiowide", "Audiowide" },
    { "orbitron", "Orbitron", "Orbitron-Black" }, { "chakra", "Chakra Petch", "ChakraPetch-Bold" },
    { "rubikmono", "Rubik Mono", "RubikMonoOne", true },
    -- Azeroth
    { "cinzel", "Cinzel", "Cinzel-Black" }, { "metamorphous", "Metamorphous", "Metamorphous" },
    { "pirata", "Pirata One", "PirataOne", true }, { "medieval", "MedievalSharp", "MedievalSharp", true },
    -- fun
    { "marker", "Permanent Marker", "PermanentMarker", true }, { "pressstart", "Press Start 2P", "PressStart2P", true },
    { "bungee", "Bungee", "Bungee" }, { "righteous", "Righteous", "Righteous" },
    { "glitch", "Rubik Glitch", "RubikGlitch", true }, { "kanit", "Kanit Black Italic", "Kanit-BlackItalic" },
    { "alfaslab", "Alfa Slab One", "AlfaSlabOne" }, { "changa", "Changa One", "ChangaOne" },
    { "archivoblack", "Archivo Black", "ArchivoBlack" },
    -- soft, rounded
    { "fredoka", "Fredoka", "Fredoka-SemiBold" }, { "baloo", "Baloo 2", "Baloo2-ExtraBold" },
    { "nunito", "Nunito Black", "Nunito-Black" }, { "varela", "Varela Round", "VarelaRound" },
    { "mplus", "M PLUS Rounded", "MPLUSRounded-ExtraBold" }, { "sniglet", "Sniglet", "Sniglet-ExtraBold" },
    { "comfortaa", "Comfortaa", "Comfortaa-Bold" }, { "quicksand", "Quicksand", "Quicksand-Bold" },
    { "grandstander", "Grandstander", "Grandstander-Black" }, { "rubik", "Rubik", "Rubik-Bold" },
    { "mali", "Mali", "Mali-Bold" }, { "itim", "Itim", "Itim" }, { "delius", "Delius", "Delius" },
    { "dosis", "Dosis", "Dosis-ExtraBold" }, { "gluten", "Gluten", "Gluten-SemiBold" },
}
-- The setup guide's font cards: UI fonts only.
Style.FONT_PICKS = { "expressway", "ptsans", "archivo", "barlow", "fira", "poppins", "lato", "russo", "game", "arialn" }
Style.FONT_ORDER = { "expressway", "ptsans", "archivo", "barlow", "fira", "poppins", "lato", "russo" }
for _, d in ipairs(DISPLAY) do
    Style.FONTS[d[1]] = { label = d[2], file = FONTS .. d[3] .. ".ttf", display = d[4] }
    Style.FONT_ORDER[#Style.FONT_ORDER + 1] = d[1]
end
Style.FONT_ORDER[#Style.FONT_ORDER + 1] = "game"
Style.FONT_ORDER[#Style.FONT_ORDER + 1] = "arialn"
Style.FONT = Style.FONTS.expressway.file

-- Sets Style.FONT from the Appearance setting: one of ours, or a shared font
-- ("lsm:<name>", ours until its addon has registered it).
-- The client's own font, even after "Use this font for the game's text" replaced it.
local function clientFont()
    return DUI.GameFonts and DUI.GameFonts.ClientFont() or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- The file for a font pick: one of ours, a shared one (ours until its addon
-- registers it), or the client's (Game font, or "Use my language's font").
function Style.FontFileOf(key)
    local shared = DUI.Media and DUI.Media.Fetch("font", key)
    if shared then return shared end
    local f = Style.FONTS[key] or Style.FONTS.expressway
    return (f.game or DUI.DB.UseLocalFont()) and clientFont() or f.file
end

-- A slot's font (Media.RegisterSlot): its own pick, else the Appearance font.
function Style.FontFile(slot)
    local own = slot and DUI.Media and DUI.Media.Pick(slot)
    return own and Style.FontFileOf(own) or Style.FONT
end

function Style.PickFont()
    local on = DUI.DB.UseLocalFont()
    local client = clientFont()
    Style.FONT = Style.FontFileOf(DUI.DB.General().font)
    if DUI.Widgets then
        DUI.Widgets.BODY = on and client or DUI.OptionsTheme.BodyFont()
        DUI.Widgets.TITLE = Style.FONT
    end
end

Style.BORDER = { 0.024, 0.024, 0.027 }      -- #060607
Style.BAND = { 0.10, 0.09, 0.065 } -- the heavy border's warm band
Style.BAND_LIT = { 0.2, 0.185, 0.14 } -- its lit top line
Style.HEAVY_MIN_PX = 3 -- thinner borders stay plain
Style.BACKGROUND = { 0.078, 0.078, 0.090 }  -- #141417
Style.BACKGROUND_ALPHA = 0.85

-- A panel's background opacity (chat, info panel, quest box, buffs): its own
-- when its "Separate ... background opacity" switch is on, else the shared
-- window value (General windowAlpha). Read at paint time; General's repaint
-- reaches the panels through their modules' OnStyleChanged.
function Style.BackAlpha(own, value)
    if own == true and type(value) == "number" then return value end
    local g = DUI.DB and DUI.DB.General and DUI.DB.General()
    return g and type(g.windowAlpha) == "number" and g.windowAlpha or Style.BACKGROUND_ALPHA
end

-- A window's background opacity. scope is the module holding its windowAlpha
-- and windowAlphaOwn (Style.Shell's opts.window, Win.New's spec.back). true
-- (a small window with no setting of its own) uses the shared value.
function Style.WindowBack(scope)
    if type(scope) ~= "string" then return Style.BackAlpha() end
    return Style.BackAlpha(DUI:Get(scope, "windowAlphaOwn"), DUI:Get(scope, "windowAlpha"))
end
Style.NEUTRAL = { 0.42, 0.42, 0.44 }
Style.ACCENT = { 0.72, 0.7, 0.66 } -- #b8b3a8, a soft warm gray that's easy on the eyes

-- Text colors by meaning, the one set all our text paints from: tooltips,
-- windows, panels and the options window alike. Brightest to dimmest: TITLE
-- and VALUE white, TEXT soft white, LABEL tan, OFF dim, all warm and never a
-- neutral gray. Color only where a glance needs it (Style.Pop) or when a thing
-- has a color of its own (quality, difficulty, class).
Style.INK = {
    TITLE = { 1, 1, 1 }, -- a tooltip's or card's title
    VALUE = { 1, 1, 1 }, -- a number, a name, a value
    TEXT  = { 0.949, 0.933, 0.902 }, -- #f2eee6 soft white: a sentence, a row, a button, what a click does
    LABEL = { 0.76, 0.71, 0.62 }, -- a label, an unselected tab, "nothing here"
    OFF   = { 0.55, 0.51, 0.45 }, -- truly unavailable: locked, not learned, empty
    GOOD  = { 0.55, 0.85, 0.55 }, -- done, complete
    WARN  = { 0.95, 0.72, 0.32 }, -- in progress, running low
    BAD   = { 0.93, 0.36, 0.30 }, -- not started, nearly out
    DAMAGE = { 0.93, 0.50, 0.44 }, -- a damage amount in a sentence, softer than BAD (which means "out")
    MONEY = { 1, 0.82, 0 },         -- gold
}

-- The pop color: the player's accent, read at paint time (Style.Accent is below).
function Style.Pop() return Style.Accent() end

-- Paints a font string in a Style.INK role, or "pop" for the accent.
function Style.InkText(fs, role, a)
    if role == "pop" then
        local r, g, b = Style.Accent()
        fs:SetTextColor(r, g, b, a or 1)
    else
        local c = Style.INK[role] or Style.INK.TEXT
        fs:SetTextColor(c[1], c[2], c[3], a or 1)
    end
end
Style.REACTION = {
    hostile = { 0.85, 0.22, 0.20 },
    neutral = { 0.95, 0.78, 0.25 },
    friendly = { 0.30, 0.78, 0.32 },
}
Style.CAST = { normal = { 0.78, 0.62, 0.30 }, locked = { 0.42, 0.42, 0.45 } }
-- Power colors that replace Blizzard's where its base is too harsh to soften well.
Style.POWER = { MANA = { 0.22, 0.42, 0.86 } }
Style.POWER_FALLBACK = { 0.22, 0.42, 0.86 }

local function general() return DUI.DB.General() end
local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Colors

-- Dark and soft: pull the color toward its own gray (softness), then dim it
-- (brightness), so class colors look muted rather than pastel.
function Style.Soften(r, g, b, amount, brightness)
    local gen = general()
    local base = DUI.DB.GENERAL_DEFAULTS
    amount = amount or gen.softness or base.softness
    brightness = brightness or gen.brightness or base.brightness
    local gray = r * 0.299 + g * 0.587 + b * 0.114
    r, g, b = r + (gray - r) * amount, g + (gray - g) * amount, b + (gray - b) * amount
    return r * brightness, g * brightness, b * brightness
end

function Style.Lighten(r, g, b, amount)
    return r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount
end

-- Aura times. The client writes an aura button's time itself (the time can be
-- secret), and by default it writes "13 m". This formatter makes it "13m",
-- "7s", "2h": whole units, the largest that fits.

-- Under a second shows nothing. An aura with no end reports 0 left, and "0s"
-- on it would read as expiring.
Style.DURATION_STEPS = {
    { threshold = 0, format = "" },
    { threshold = 1, format = "%ds" },
    { threshold = 60, format = "%dm", div = 60 },
    { threshold = 3600, format = "%dh", div = 3600 },
    { threshold = 86400, format = "%dd", div = 86400 },
}

local durationFormatters = {}

-- upTo: seconds from which nothing is shown (a time shown only once it runs
-- low). nil shows every time.
function Style.DurationFormatter(upTo)
    local key = upTo or "all"
    if durationFormatters[key] ~= nil then return durationFormatters[key] or nil end
    durationFormatters[key] = false
    local make = C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
    if type(make) ~= "function" then return nil end
    local rounding = Enum and Enum.NumericRuleFormatRounding
    local steps = {}
    for _, s in ipairs(Style.DURATION_STEPS) do
        if upTo and s.threshold >= upTo then break end
        local step = { threshold = s.threshold, format = s.format, step = 1 }
        if rounding and rounding.Down then step.rounding = rounding.Down end
        if s.div then step.components = { { div = s.div, step = 1 } } end
        steps[#steps + 1] = step
    end
    if upTo then steps[#steps + 1] = { threshold = upTo, format = "", step = 1 } end
    local ok, f = pcall(make)
    if ok and f and pcall(f.SetBreakpoints, f, steps) then durationFormatters[key] = f end
    return durationFormatters[key] or nil
end

-- A clock for bar times: "5", "42", "2:58", and "1h" over an hour. Rounded up
-- to the second like a countdown. The rounding is applied to the whole value
-- first (the parts only divide), so 59.6 reads "1:00", never "0:60" or "60"
-- (the format EllesmereUI ships on this client): each step starts just past
-- the last value the previous one can show. Nothing at 0, since an aura with
-- no end reports 0 left.
Style.CLOCK_STEPS = {
    { threshold = 0, format = "" },
    { threshold = 0.001, format = "%d", round = true },
    { threshold = 59.0001, format = "%d:%02d", parts = { { div = 60 }, { mod = 60 } } },
    { threshold = 3599.0001, format = "%dh", parts = { { div = 3600 } } },
}

local clockFormatter

function Style.ClockFormatter()
    if clockFormatter ~= nil then return clockFormatter or nil end
    clockFormatter = false
    local make = C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
    if type(make) ~= "function" then return nil end
    local rounding = Enum and Enum.NumericRuleFormatRounding
    local steps = {}
    for i, s in ipairs(Style.CLOCK_STEPS) do
        local step = { threshold = s.threshold, format = s.format }
        if s.parts or s.round then
            step.step = 1
            if rounding and rounding.Up then step.rounding = rounding.Up end
            step.components = s.parts
        end
        steps[i] = step
    end
    local ok, f = pcall(make)
    if ok and f and pcall(f.SetBreakpoints, f, steps) then clockFormatter = f end
    return clockFormatter or nil
end

-- Hands an aura button its time text, in our format when the client has the
-- formatter (the client's own otherwise).
-- textColor (optional): the client's color curve on the time left
-- (DurationTextBindingColorOptions). If refused, the time shows plain.
-- formatter (optional): another of ours (Style.ClockFormatter for bars).
function Style.SetAuraTime(btn, fs, textColor, formatter)
    local f = formatter or Style.DurationFormatter()
    if textColor and pcall(btn.SetDurationText, btn, fs, { textFormatter = f, textColor = textColor }) then return true end
    if f and pcall(btn.SetDurationText, btn, fs, { textFormatter = f }) then return end
    btn:SetDurationText(fs)
end

-- A soft light behind an aura button, shown by the client only on a buff you
-- can purge or steal, in its dispel type's color. Nothing is read, so it stays
-- correct in combat. colors maps dispel type -> { r, g, b }. harmful puts it
-- on debuffs with a dispel type instead (the button's group decides which
-- debuffs, e.g. the target's ones you can dispel). every puts it on any buff,
-- for a row whose filter already picked only those (nameplates). Returns the
-- texture, or nil when the client refuses.
Style.AURA_HALO = DUI.MEDIA .. "glow.png"
Style.AURA_HALO_REACH = 0.5 -- how far it spreads past the icon, as a share of its width
function Style.AuraHalo(btn, colors, harmful, every)
    local styles = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    local steal = Enum and Enum.CustomAuraButtonDispelTypeStealableFilter
    if not (btn.AddDispelTypeTexture and styles and styles.CustomAsset and steal) then return nil end
    local halo = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    halo:SetTexture(Style.AURA_HALO)
    halo:SetBlendMode("ADD")
    -- A buff without a type (rare on a purgeable one) takes Magic's light.
    local assets, tints = dispelSet(colors, Style.AURA_HALO, nil, "Magic")
    local ok = pcall(btn.AddDispelTypeTexture, btn, halo, {
        showWhenHarmful = harmful and true or false, showWhenHelpful = not harmful,
        showWithoutDispelType = not harmful, stealableFilter = not (harmful or every) and steal.Stealable or nil,
        style = styles.CustomAsset,
        customDispelAssetMap = assets, customDispelColorMap = tints,
    })
    if not ok then halo:Hide() return nil end
    return halo
end

-- Fits a halo to its button's width w (where the button is sized).
function Style.PlaceAuraHalo(halo, btn, w)
    if not halo then return end
    local d = w * Style.AURA_HALO_REACH
    halo:ClearAllPoints()
    halo:SetPoint("TOPLEFT", btn, "TOPLEFT", -d, d)
    halo:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", d, -d)
end

function Style.Neutral()
    local n = Style.NEUTRAL
    return n[1], n[2], n[3]
end

-- The accent: Daylight's warm gray (Style.ACCENT), the Daylight gradient's
-- middle purple, the player's class color, the class gradient pair, or a
-- custom color (the Appearance setting). Everything that highlights asks for
-- it here, so a change repaints them all.
Style.ACCENTS = { daylight = "Daylight", gradient = "Daylight gradient", class = "Class color",
    classGradient = "Class gradient", custom = "Custom color" }
Style.ACCENT_ORDER = { "daylight", "gradient", "class", "classGradient", "custom" }
-- The Daylight gradient (the logo's, blue to orange). Filled shapes sweep
-- across it, while text and thin lines take its middle purple, or in a list
-- each row takes its own spot along the sweep (Style.AccentAt).
Style.GRADIENT = { { 0.118, 0.565, 1 }, { 1, 0.604, 0.122 } }
Style.GRADIENT_MID = { 0.635, 0.369, 0.780 }      -- #a25ec7
-- The whole sweep (blue, purple, pink, orange) as an image, for a bar or a
-- line. A plain two-color blend from blue to orange passes through gray, so a
-- shape's own blend stops at the pink instead.
Style.GRADIENT_FILE = DUI.MEDIA .. "gradient-daylight.png"
Style.GRADIENT_SHAPE = { { 0.118, 0.565, 1 }, { 0.902, 0.353, 0.447 } }   -- #1e90ff to #e65a72

-- The class gradient accent: the player's class pair (General > Gradients,
-- palette and edits included, unsoftened like the class color accent), with
-- its dark end lifted CLASS_LIFT toward the light one so a line or word at
-- that end still reads on our dark frames. The same tables are kept until
-- the pair's numbers change, so a painter caching on them stays valid.
Style.CLASS_LIFT = 0.35
local classPair = { raw = {} }

local function classAccent()
    local G = DUI.Gradients
    local _, token = UnitClass("player")
    if not G or type(token) ~= "string" or not G.Has(token) then return nil end
    local lo, hi = G.RGB(token)
    local c, raw = classPair, classPair.raw
    if c.token ~= token or raw[1] ~= lo[1] or raw[2] ~= lo[2] or raw[3] ~= lo[3]
        or raw[4] ~= hi[1] or raw[5] ~= hi[2] or raw[6] ~= hi[3] then
        local k = Style.CLASS_LIFT
        c.token, c.raw = token, { lo[1], lo[2], lo[3], hi[1], hi[2], hi[3] }
        c.lo = { lo[1] + (hi[1] - lo[1]) * k, lo[2] + (hi[2] - lo[2]) * k, lo[3] + (hi[3] - lo[3]) * k }
        c.hi = { hi[1], hi[2], hi[3] }
        c.mid = { (c.lo[1] + hi[1]) / 2, (c.lo[2] + hi[2]) / 2, (c.lo[3] + hi[3]) / 2 }
    end
    return c
end

-- The class gradient accent's two ends regardless of the current accent (the
-- setup guide's swatch). Nil while the class isn't known.
function Style.ClassAccentPair()
    local c = classAccent()
    if c then return c.lo, c.hi end
end

-- Which gradient the accent is: "daylight" (the logo's sweep), "class" (the
-- class pair) or nil (a single color). The class one falls back to a single
-- color while the class isn't known.
function Style.AccentSweep()
    if DUI.Gradients and DUI.Gradients.Flat() then return nil end -- General > Gradients off means one color
    local a = general().accent
    if a == "gradient" then return "daylight" end
    if a == "classGradient" and classAccent() then return "class" end
    return nil
end

function Style.GradientAccent() return Style.AccentSweep() ~= nil end

-- A gradient accent's two ends for a shape or line, left to right, as
-- { r, g, b } (shared tables, don't modify), or nil for a single-color accent.
-- The Daylight one stops at the pink (Style.GRADIENT_SHAPE).
function Style.AccentPair()
    local kind = Style.AccentSweep()
    if kind == "daylight" then return Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2] end
    if kind == "class" then
        local c = classAccent()
        return c.lo, c.hi
    end
    return nil
end

-- The whole sweep's stops (blue, purple, pink, orange), as DUI.GradientText uses.
Style.SWEEP = { { 0.118, 0.565, 1 }, { 0.635, 0.369, 0.780 }, { 0.902, 0.353, 0.447 }, { 1, 0.604, 0.122 } }

-- The accent at position t down a list (0 to 1). With a gradient accent it's
-- that spot along it, so a list runs blue to orange (or dark to light in the
-- class pair); otherwise just the accent.
function Style.AccentAt(t)
    local kind = type(t) == "number" and Style.AccentSweep()
    if kind == "daylight" then return Style.SweepAt(t) end
    if kind == "class" then
        local c = classAccent()
        local lo, hi = c.lo, c.hi
        t = math.max(0, math.min(1, t))
        return lo[1] + (hi[1] - lo[1]) * t, lo[2] + (hi[2] - lo[2]) * t, lo[3] + (hi[3] - lo[3]) * t
    end
    return Style.Accent()
end

-- Text in the accent. With a gradient accent it's colored letter by letter
-- along it (draw on a white font color); otherwise unchanged. Returns the
-- text and whether it was colored. Anything that isn't a plain string (a
-- secret name) is returned unchanged.
function Style.AccentText(text)
    local kind = Style.AccentSweep()
    if not kind or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or text == "" then
        return text, false
    end
    if kind == "daylight" then return DUI.GradientText(text), true end
    local chars, out = {}, {}
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    local n = #chars
    for i, ch in ipairs(chars) do
        local r, g, b = Style.AccentAt(n > 1 and (i - 1) / (n - 1) or 0.5)
        out[i] = string.format("|cff%02x%02x%02x%s", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
            math.floor(b * 255 + 0.5), ch)
    end
    return table.concat(out) .. "|r", true
end

-- Paints a font string in the accent: letter by letter with a gradient
-- accent, otherwise the single color.
function Style.PaintAccentText(fs, text)
    local coloured, on = Style.AccentText(text)
    fs:SetText(coloured)
    if on then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(Style.Accent()) end
end

-- A showpiece's sweep (the level-up light): the class pair when the class
-- gradient is the accent, else the Daylight sweep regardless of accent.
function Style.SplashAt(t)
    if Style.AccentSweep() == "class" then return Style.AccentAt(t) end
    return Style.SweepAt(t)
end

-- The spot t (0 to 1) along the Daylight sweep regardless of accent. No t
-- means the middle purple (a list of one).
function Style.SweepAt(t)
    if type(t) ~= "number" then
        local m = Style.GRADIENT_MID
        return m[1], m[2], m[3]
    end
    local stops = Style.SWEEP
    t = math.max(0, math.min(1, t)) * (#stops - 1)
    local i = math.min(#stops - 1, math.floor(t) + 1)
    local f, a, b = t - (i - 1), stops[i], stops[i + 1]
    return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f
end

function Style.Accent()
    local g = general()
    if g.accent == "custom" then
        local c = g.accentColor
        if type(c) == "table" and type(c[1]) == "number" then return c[1], c[2], c[3] end
    end
    if g.accent == "gradient" then
        local m = Style.GRADIENT_MID
        return m[1], m[2], m[3]
    end
    if g.accent == "classGradient" then
        local c = classAccent()
        if c then return c.mid[1], c.mid[2], c.mid[3] end
    end
    if g.accent == "class" or g.accent == "classGradient" then
        local _, token = UnitClass("player")
        local r, gr, b = Style.RawClassColor(token)
        if r then return r, gr, b end
    end
    local a = Style.ACCENT
    return a[1], a[2], a[3]
end

-- A filled shape in the accent: the gradient across it when the accent is a
-- gradient, otherwise the single color. (A plain vertex color set afterward
-- clears a gradient, so switching back needs nothing more.) orientation is
-- optional; "VERTICAL" runs bottom (dark) to top (light).
function Style.PaintAccent(tex, alpha, orientation)
    alpha = alpha or 1
    local a, b = Style.AccentPair()
    if a and tex.SetGradient and CreateColor then
        tex:SetVertexColor(1, 1, 1, alpha)
        tex:SetGradient(orientation or "HORIZONTAL", CreateColor(a[1], a[2], a[3], alpha), CreateColor(b[1], b[2], b[3], alpha))
        return
    end
    local r, g, b = Style.Accent()
    tex:SetVertexColor(r, g, b, alpha)
end

-- A class's own color, unsoftened: a class color addon's (CUSTOM_CLASS_COLORS)
-- first, else the game's. Returns r, g, b, or nil for a secret, missing or unknown token.
function Style.RawClassColor(token)
    if type(token) ~= "string" or isSecret(token) then return nil end
    local c = type(CUSTOM_CLASS_COLORS) == "table" and CUSTOM_CLASS_COLORS[token]
    if type(c) ~= "table" or type(c.r) ~= "number" then
        c = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[token]
    end
    if type(c) ~= "table" or type(c.r) ~= "number" then return nil end
    return c.r, c.g, c.b
end

function Style.ClassColor(token)
    local r, g, b = Style.RawClassColor(token)
    if not r then return Style.Neutral() end
    return Style.Soften(r, g, b)
end

-- The same for text. A class that can't be read (secret, missing, unknown) is
-- warm white (INK.VALUE) rather than the bars' neutral gray.
function Style.ClassTextColor(token)
    if isSecret(token) or token == nil then return Style.INK.VALUE[1], Style.INK.VALUE[2], Style.INK.VALUE[3] end
    if not Style.RawClassColor(token) then return Style.INK.VALUE[1], Style.INK.VALUE[2], Style.INK.VALUE[3] end
    return Style.ClassColor(token)
end

function Style.ReactionColor(reaction)
    if isSecret(reaction) or reaction == nil then return Style.Neutral() end
    local c
    if reaction <= 3 then
        c = Style.REACTION.hostile
    elseif reaction == 4 then
        c = Style.REACTION.neutral
    else
        c = Style.REACTION.friendly
    end
    return Style.Soften(c[1], c[2], c[3])
end

function Style.PowerColor(token)
    local known = not isSecret(token) and token ~= nil
    local own = known and Style.POWER[token]
    if own then return Style.Soften(own[1], own[2], own[3]) end
    local c = known and PowerBarColor and PowerBarColor[token]
    if c then return Style.Soften(c.r, c.g, c.b) end
    local f = Style.POWER_FALLBACK
    return Style.Soften(f[1], f[2], f[3])
end

-- Shell: shadow outside, rounded border, faint bevel, translucent background.
-- It only adds layers to the frame it's given, so it works on any frame.
-- Lookups use weak-keyed tables, never fields on the frame.

local shellOf = setmetatable({}, { __mode = "k" })
local shells = setmetatable({}, { __mode = "k" })

local CORNER_KEYS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local ENDS = { "left", "right" }
local EDGE_KEYS = { "TOP", "BOTTOM", "LEFT", "RIGHT" }
-- The end a border piece lies at (top and bottom run end to end).
local END_OF = { LEFT = "left", TOPLEFT = "left", BOTTOMLEFT = "left",
    RIGHT = "right", TOPRIGHT = "right", BOTTOMRIGHT = "right" }
-- Every outline piece, the shadow sides a seam can hide (with their corners),
-- and each end's top and bottom corner points. Key lists are built once
-- because a layout runs for every plate in a crowd.
local BORDER_KEYS = { "TOP", "BOTTOM", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local SEAM_PIECES = { { "TOP", "TOPLEFT", "TOPRIGHT" }, { "BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT" } }
local TOP_AT = { left = "TOPLEFT", right = "TOPRIGHT", LEFT = "TOPLEFT", RIGHT = "TOPRIGHT" }
local BOTTOM_AT = { left = "BOTTOMLEFT", right = "BOTTOMRIGHT", LEFT = "BOTTOMLEFT", RIGHT = "BOTTOMRIGHT" }
local CORNER_COORDS = {
    TOPLEFT = { 0, 1, 0, 1 }, TOPRIGHT = { 1, 0, 0, 1 },
    BOTTOMLEFT = { 0, 1, 1, 0 }, BOTTOMRIGHT = { 1, 0, 1, 0 },
}
-- Corner caps sit just inside the border at each corner.
local FILLET_SIGN = {
    TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 },
}
-- Masks that clear the inside of a rounded corner piece, leaving its ring. The
-- pieces are solid quarter discs that a frame's bars cover, but a frame with
-- only a background (a name tab, a tooltip) would show them.
local HOLE = {
    TOPLEFT = DUI.MEDIA .. "mask-hole-tl.png", TOPRIGHT = DUI.MEDIA .. "mask-hole-tr.png",
    BOTTOMLEFT = DUI.MEDIA .. "mask-hole-bl.png", BOTTOMRIGHT = DUI.MEDIA .. "mask-hole-br.png",
}
local OPPOSITE = { TOPLEFT = "BOTTOMRIGHT", TOPRIGHT = "BOTTOMLEFT", BOTTOMLEFT = "TOPRIGHT", BOTTOMRIGHT = "TOPLEFT" }
-- Shadow corners are centered on the border's inner corner point.
local SHADOW_ANCHOR = {
    TOPLEFT = { "BOTTOMRIGHT", 1, -1 }, TOPRIGHT = { "BOTTOMLEFT", -1, -1 },
    BOTTOMLEFT = { "TOPRIGHT", 1, 1 }, BOTTOMRIGHT = { "TOPLEFT", -1, 1 },
}

-- The shell's art and placements, for a frame that draws the same look its own
-- way (the nameplates' lean border, DaylightUI_Nameplates/Body.lua).
Style.SHELL_ART = {
    CORNER = CORNER, SHADOW = SHADOW, FILLET = FILLET, CORNER_COORDS = CORNER_COORDS,
    FILLET_SIGN = FILLET_SIGN, SHADOW_ANCHOR = SHADOW_ANCHOR, ShadowRound = shadowRound,
}

local function cornerTexture(parent, layer, sublevel, file, key)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetTexture(file, "CLAMP", "CLAMP")
    t:SetTexCoord(unpack(CORNER_COORDS[key]))
    return t
end

function Style.Shell(frame, opts)
    if frame.IsForbidden and frame:IsForbidden() then return nil end -- the game's, closed to addons
    if opts and opts.window then Style.MarkWindow(frame) end
    local s = shellOf[frame]
    if s then
        if opts then s.opts = opts end
        Style.LayoutShell(s)
        return s
    end
    s = CreateFrame("Frame", nil, frame)
    s:SetAllPoints(frame)
    s:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    s:EnableMouse(false)
    s.opts = opts or {}
    -- opts.lean: a small icon's shell with a thin border that's never heavy,
    -- angled, filled or beveled (aura buttons, which the client builds ten per
    -- group whether they show or not). Only the outline, its caps and the shadow
    -- are created (with noBorder only the shadow) and it draws the same. Fixed at
    -- creation: such a shell can't take those looks later.
    s.lean = s.opts.lean == true
    local outline = not (s.lean and s.opts.noBorder)
    s.border, s.shadow = {}, {}
    for _, key in ipairs(CORNER_KEYS) do
        if outline then s.border[key] = cornerTexture(s, "BORDER", 0, CORNER, key) end
        s.shadow[key] = cornerTexture(s, "BACKGROUND", -8, SHADOW, key)
    end
    for _, key in ipairs(EDGE_KEYS) do
        if outline then
            local e = s:CreateTexture(nil, "BORDER", nil, 0)
            e:SetTexture(WHITE)
            s.border[key] = e
        end
        local se = s:CreateTexture(nil, "BACKGROUND", nil, -8)
        se:SetTexture(WHITE)
        s.shadow[key] = se
    end
    s.slantFill, s.band, s.bandSlant, s.lineSlant, s.fillet = {}, {}, {}, {}, {}
    if s.lean then return Style.FinishShell(frame, s, outline) end
    s.bg = s:CreateTexture(nil, "BACKGROUND", nil, -7)
    -- Solid border color behind an angled end, so the cut reads as border.
    for _, side in ipairs(ENDS) do
        local t = s:CreateTexture(nil, "BORDER", nil, 0)
        t:SetTexture(WHITE)
        t:Hide()
        s.slantFill[side] = t
    end
    -- The heavy border: a warm band inside the black outline, lit along its top,
    -- with a black line between it and the contents. At an angled end the band
    -- and that line are fills clipped to their own inset lines.
    for _, key in ipairs(CORNER_KEYS) do s.band[key] = cornerTexture(s, "BORDER", 1, CORNER, key) end
    for _, key in ipairs(EDGE_KEYS) do
        local e = s:CreateTexture(nil, "BORDER", nil, 1)
        e:SetTexture(WHITE)
        s.band[key] = e
    end
    for _, side in ipairs(ENDS) do
        s.bandSlant[side] = s:CreateTexture(nil, "BORDER", nil, 1)
        s.bandSlant[side]:SetTexture(WHITE)
        s.lineSlant[side] = s:CreateTexture(nil, "BORDER", nil, 2)
        s.lineSlant[side]:SetTexture(WHITE)
    end
    s.lit = s:CreateTexture(nil, "BORDER", nil, 2)
    s.lit:SetTexture(WHITE)
    s.bevelTop = s:CreateTexture(nil, "BORDER", nil, 1)
    s.bevelBottom = s:CreateTexture(nil, "BORDER", nil, 1)
    return Style.FinishShell(frame, s, true)
end

-- The rest of a new shell, lean or not: its corner caps, then its first layout.
function Style.FinishShell(frame, s, outline)
    -- Corner caps sit above the frame's contents, so when the corner is rounder
    -- than the border is thick, the bars' corners follow the curve. They're a
    -- child of the shell so they fade and hide with it (an empty action slot's
    -- shell at alpha 0 left them as dots at its corners).
    if outline then
        s.over = CreateFrame("Frame", nil, s)
        s.over:SetAllPoints(frame)
        s.over:SetFrameLevel(frame:GetFrameLevel() + 10)
        s.over:EnableMouse(false)
        for _, key in ipairs(CORNER_KEYS) do s.fillet[key] = cornerTexture(s.over, "OVERLAY", 7, FILLET, key) end
    end
    shellOf[frame] = s
    shells[s] = true
    -- Laid out again when next shown if the style changed while hidden
    -- (Style.RepaintAll skips hidden shells). A shell on a frame the client
    -- restricts (an aura button in its container) can't take a script, so it's
    -- laid out immediately on every change instead. So is a quiet one: its
    -- OnShow would run inside the game's own Show of the frame, before the
    -- frame's OnShow, and taint what the game does there.
    local deferrable = not s.opts.quiet and pcall(s.SetScript, s, "OnShow", function(self)
        if self.dirty then Style.LayoutShell(self) end
    end)
    s.alwaysLayout = not deferrable
    Style.LayoutShell(s)
    return s
end

function Style.GetShell(frame) return shellOf[frame] end
-- Every shell created (the login reveal looks for the visible ones).
function Style.Shells() return pairs(shells) end

-- A shell's border thickness in screen pixels: its own (a number, or a
-- function of the general one), else the general setting.
local function shellBorderPx(s)
    local own = s and s.opts.borderPx
    if type(own) == "function" then return own(general().borderPx) end
    return own or general().borderPx
end

function Style.BorderPx(frame) return shellBorderPx(shellOf[frame]) end

-- Recolors a shell's outline and heavy band (nil restores normal). For a
-- highlight such as aggro. Only repaints on an actual change, compared by
-- value (the same color in a new table is no change).
local function sameColor(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

-- The accent's pair in the form a shell takes ({ lo, hi }), one table per pair.
local shellPair = {}
local function accentShellPair(lo, hi)
    if shellPair[1] ~= lo or shellPair[2] ~= hi then shellPair = { lo, hi } end
    return shellPair
end

-- pair: optional { lo, hi } ({ r, g, b } each) for the outline to sweep across,
-- left to right, instead of the single border color.
function Style.SetShellColors(s, border, band, pair)
    local old = s.opts.borderPair
    local samePair = old == pair or (type(old) == "table" and type(pair) == "table"
        and sameColor(old[1], pair[1]) and sameColor(old[2], pair[2]))
    if samePair and sameColor(s.opts.borderColor, border) and sameColor(s.opts.bandColor, band) then return end
    s.opts.borderColor, s.opts.bandColor, s.opts.borderPair = border, band, pair
    -- Colors only, nothing moves (a full layout was about 100 calls, and threat
    -- recolors every frame and plate).
    Style.PaintShellColors(s)
end

-- A shell lit in the accent (a hovered or selected thing): the border in the
-- accent, its outline sweeping along a gradient accent. bandK (optional) dims
-- the band's accent to that share, otherwise the band stays normal.
function Style.LightShell(s, bandK)
    local r, g, b = Style.Accent()
    local band = type(bandK) == "number" and { r * bandK, g * bandK, b * bandK } or nil
    local lo, hi = nil, nil
    if CreateColor then lo, hi = Style.AccentPair() end
    Style.SetShellColors(s, { r, g, b }, band, lo and accentShellPair(lo, hi) or nil)
end

-- Same, from a secret boolean: the client picks the color per piece. border
-- and band are the highlight colors; false gives the normal ones. The four
-- color objects are kept on the shell until one of them changes.
local function boolColors(s, border, band, a)
    local c = s.boolColors
    if c and c.a == a and c.b1 == border[1] and c.b2 == border[2] and c.b3 == border[3]
       and c.d1 == band[1] and c.d2 == band[2] and c.d3 == band[3] then
        return c
    end
    local nb, nd = Style.BORDER, Style.BAND
    c = { a = a, b1 = border[1], b2 = border[2], b3 = border[3], d1 = band[1], d2 = band[2], d3 = band[3],
          onB = CreateColor(border[1], border[2], border[3], a), offB = CreateColor(nb[1], nb[2], nb[3], a),
          onD = CreateColor(band[1], band[2], band[3], a), offD = CreateColor(nd[1], nd[2], nd[3], a) }
    s.boolColors = c
    return c
end

local function eachFromBoolean(list, flag, on, off)
    for _, tex in pairs(list) do
        if tex.SetVertexColorFromBoolean then tex:SetVertexColorFromBoolean(flag, on, off) end
    end
end

function Style.ShellColorsFromBoolean(s, flag, border, band)
    local c = boolColors(s, border, band, general().borderAlpha)
    eachFromBoolean(s.border, flag, c.onB, c.offB)
    eachFromBoolean(s.slantFill, flag, c.onB, c.offB)
    eachFromBoolean(s.lineSlant, flag, c.onB, c.offB)
    eachFromBoolean(s.band, flag, c.onD, c.offD)
    eachFromBoolean(s.bandSlant, flag, c.onD, c.offD)
end

-- opts.heavyMinPx: a shell's own minimum for a heavy border (a thin bar's band
-- and lines need more room than a frame's).
function Style.IsHeavy(s)
    return general().heavyBorder ~= false and not s.opts.flat
        and shellBorderPx(s) >= (s.opts.heavyMinPx or Style.HEAVY_MIN_PX)
end

-- Clears a corner piece inside radius r around the curve's center, which
-- sits R in from the corner on both axes. r <= 0 leaves it whole.
local function hole(s, tex, key, R, r)
    s.holes = s.holes or {}
    local h = s.holes[tex]
    if r <= 0 then
        if h and h.added then
            tex:RemoveMaskTexture(h)
            h.added = false
        end
        return
    end
    if not h then
        h = s:CreateMaskTexture()
        h:SetTexture(HOLE[key], "CLAMP", "CLAMP")
        s.holes[tex] = h
    end
    local sign = FILLET_SIGN[key]
    h:ClearAllPoints()
    h:SetSize(r, r)
    h:SetPoint(OPPOSITE[key], s, key, sign[1] * R, sign[2] * R)
    if not h.added then
        tex:AddMaskTexture(h)
        h.added = true
    end
end

-- A ring corner drawn around a rounded border: a solid quarter disc, cleared
-- inside radius r around the curve's center (the piece's inner corner), so it
-- hugs the border's curve. With r <= 0, a plain square piece in `file` instead.
local ringHoles = setmetatable({}, { __mode = "k" })
function Style.RingCorner(tex, key, r, file)
    local h = ringHoles[tex]
    if r <= 0 then
        tex:SetTexture(file)
        tex:SetTexCoord(0, 1, 0, 1)
        if h and h.added then
            tex:RemoveMaskTexture(h)
            h.added = false
        end
        return
    end
    tex:SetTexture(CORNER, "CLAMP", "CLAMP")
    tex:SetTexCoord(unpack(CORNER_COORDS[key]))
    if not h then
        h = tex:GetParent():CreateMaskTexture()
        h:SetTexture(HOLE[key], "CLAMP", "CLAMP")
        ringHoles[tex] = h
    end
    h:ClearAllPoints()
    h:SetSize(r, r)
    h:SetPoint(OPPOSITE[key], tex, OPPOSITE[key], 0, 0)
    if not h.added then
        tex:AddMaskTexture(h)
        h.added = true
    end
end

-- A shell piece's color: plain, or its share of a sweep (the pair's ends
-- across the top and bottom, one end's color on each side).
local BLACK = { 0, 0, 0 }

-- A shadow's two fade colors (full and none), shared by every shell with the
-- same color table and strength, since the game's color objects are heavy.
-- color nil means black. Never modified.
local shadowColors = setmetatable({}, { __mode = "k" })
function Style.ShadowColors(color, a)
    color = color or BLACK
    local byA = shadowColors[color]
    if not byA then
        byA = {}
        shadowColors[color] = byA
    end
    local pair = byA[a]
    if not pair then
        pair = { CreateColor(color[1], color[2], color[3], a), CreateColor(color[1], color[2], color[3], 0) }
        byA[a] = pair
    end
    return pair[1], pair[2]
end

-- A sweep's two ends as colors at alpha a, cached on the sweep table per alpha
-- (checked against its numbers, since a caller may refill its pair) so a
-- repaint creates none.
local function sweepColors(sweep, a)
    local p, q = sweep[1], sweep[2]
    local byA = sweep.colors
    if not byA then
        byA = {}
        sweep.colors = byA
    end
    local c = byA[a]
    if not (c and c[3] == p[1] and c[4] == p[2] and c[5] == p[3] and c[6] == q[1] and c[7] == q[2] and c[8] == q[3]) then
        c = { CreateColor(p[1], p[2], p[3], a), CreateColor(q[1], q[2], q[3], a), p[1], p[2], p[3], q[1], q[2], q[3] }
        byA[a] = c
    end
    return c[1], c[2]
end

local function putColor(tex, key, r, g2, b2, a2, sweep)
    if sweep and tex.SetGradient then
        local p, q = sweep[1], sweep[2]
        if key == "TOP" or key == "BOTTOM" then
            tex:SetVertexColor(1, 1, 1, a2)
            tex:SetGradient("HORIZONTAL", sweepColors(sweep, a2))
            return
        end
        local e = (key == "left" or string.find(key, "LEFT")) and p or q
        tex:SetVertexColor(e[1], e[2], e[3], a2)
        return
    end
    tex:SetVertexColor(r, g2, b2, a2)
end

-- noBorder: the shell keeps its shadow but draws no border (something else,
-- such as a dispel-colored edge, acts as the border).
local function shellAlpha(s, g)
    return s.opts.noBorder and 0 or s.opts.borderAlpha or g.borderAlpha
end

-- Sets only the outline's and band's colors, no layout: the outline's pieces
-- (corners, edges, fillets, the angled end's strips and inner line) in the
-- border color, the band's in the band color.
-- With the gradient window border option, the colored layer (the band when
-- heavy, otherwise the outline) sweeps along a gradient accent (Daylight's
-- blue to orange, or the class pair). Top and bottom run across, and each
-- side's pieces take the sweep's end on that side. A highlight color on the
-- shell wins over it. A shell's own pair (borderPair, e.g. a tooltip's class
-- gradient) sweeps its outline the same way, over its borderColor. sweep is
-- the pair, or false.
function Style.PaintShellColors(s)
    local g = general()
    local ba = shellAlpha(s, g)
    local opts = s.opts
    local lo, hi
    if g.gradientBorder and CreateColor ~= nil then lo, hi = Style.AccentPair() end
    local pair = lo and accentShellPair(lo, hi)
    local heavy = Style.IsHeavy(s)
    local own = CreateColor ~= nil and opts.borderPair or nil
    local sweepBorder = own or (pair and not heavy and not opts.borderColor and pair)
    local sweepBand = pair and heavy and not opts.bandColor and pair
    local bc, dc = opts.borderColor or Style.BORDER, opts.bandColor or Style.BAND
    local r, g2, b = bc[1], bc[2], bc[3]
    for key, tex in pairs(s.border) do putColor(tex, key, r, g2, b, ba, sweepBorder) end
    for key, tex in pairs(s.fillet) do putColor(tex, key, r, g2, b, ba, sweepBorder) end
    for side, tex in pairs(s.slantFill) do putColor(tex, side, r, g2, b, ba, sweepBorder) end
    for side, tex in pairs(s.lineSlant) do putColor(tex, side, r, g2, b, ba, sweepBorder) end
    r, g2, b = dc[1], dc[2], dc[3]
    for key, tex in pairs(s.band) do putColor(tex, key, r, g2, b, ba, sweepBand) end
    for side, tex in pairs(s.bandSlant) do putColor(tex, side, r, g2, b, ba, sweepBand) end
end

-- Is a corner piece at an angled (sharp) end?
local function sharpAt(angled, key) return angled[END_OF[key] or ""] == true end

-- Where the bottom (or top) shadow starts at an end: past the cut where it
-- meets that edge, else past the corner.
local function shadowFrom(angled, under, side, edge, E, cut, T)
    if not angled[side] then return E end
    return (leans(under, side) == (edge == "TOP")) and cut + T or T
end

-- The lit line's inset at an end: its own (e) at a square end, else where the
-- band's line crosses it (further in at an end leaning under).
local function litFrom(angled, under, side, e, inset, insetUnder)
    if not angled[side] then return e end
    return leans(under, side) and insetUnder or inset
end

-- A shell's background color. A window (opts.window) gets its opacity from
-- Style.WindowBack.
function Style.PaintBack(s)
    local bgc = s.opts.bgColor or Style.BACKGROUND
    local bgA = s.opts.bgAlpha or (s.opts.window and Style.WindowBack(s.opts.window)) or Style.BACKGROUND_ALPHA
    s.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgA)
end

-- How many shells were laid out since last asked (for profiling).
local layoutCount = 0
function Style.TakeLayoutCount()
    local n = layoutCount
    layoutCount = 0
    return n
end

function Style.LayoutShell(s)
    layoutCount = layoutCount + 1
    s.dirty = false
    local g = general()
    local borderPx = shellBorderPx(s)
    local T = DUI.Pixel.Px(s, borderPx)
    -- The corner curve is its own size, so a thick border can stay nearly
    -- square and a thin one can still be very round.
    local R = DUI.Pixel.Px(s, s.opts.cornerPx or g.cornerPx)
    -- Never rounder than half the frame's smaller side, or the shape breaks.
    -- (pcall because a shell on a client-owned aura button may not be able to read
    -- its size. A frame sized from an aura container reads back a secret number,
    -- which is still type "number" but can't be compared, so skip it.)
    local ok, w = pcall(s.GetWidth, s)
    local okH, h = pcall(s.GetHeight, s)
    ok = ok and okH
    local secret = ok and issecretvalue ~= nil and (issecretvalue(w) or issecretvalue(h))
    if ok and not secret and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
        R = math.min(R, math.min(w, h) / 2)
    end
    -- Past about 3.4x the border thickness the corner caps would poke outside
    -- the curve, so the curve stops growing there.
    if T > 0 then R = math.min(R, T * 3.4) end
    local F = math.max(0, R - T)
    s.radius = R -- the angled end's masks stay clear of the curve (LayoutSlant)
    -- A shell's own shadow size, color and strength (a glow is a colored shadow),
    -- or the general ones.
    local S = DUI.Pixel.Px(s, s.opts.shadowPx or g.shadowPx)
    local one = DUI.Pixel.Px(s, 1)
    local b, sh = s.border, s.shadow
    -- (The outline's and band's colors are set by Style.PaintShellColors at the end.)
    local ba = shellAlpha(s, g)

    -- An angled end is its own corner: sharp, with the cut as the edge. Only
    -- square ends are rounded, since a curve and a straight cut never line up and
    -- a rounded corner under the angle mask left steps and slivers.
    local sl = Style.GetSlant(s:GetParent())
    local cut = (sl and sl.side) and sl.cut or 0
    -- Kept on the shell instead of recreated: a plate in a crowd is laid out
    -- often, and every table created here was garbage for the game to collect.
    local angled = s.angled or {}
    s.angled = angled
    angled.left = sl and (sl.side == "left" or sl.side == "both") or false
    angled.right = sl and (sl.side == "right" or sl.side == "both") or false
    -- How far each end's top and bottom edges stop short of the corner, and how
    -- far its side edge starts below the top. At a sharp end the top and bottom
    -- run to the edge and cover the corner square themselves.
    local RL, RR = angled.left and 0 or R, angled.right and 0 or R
    local VL, VR = angled.left and T or R, angled.right and T or R

    if b.TOP then
    for _, key in ipairs(CORNER_KEYS) do
        local c = b[key]
        c:ClearAllPoints()
        c:SetSize(R, R)
        c:SetPoint(key, s, key, 0, 0)
        -- A zero size would draw the texture at its own size; hide instead.
        c:SetShown(R > 0 and not sharpAt(angled, key))
        -- Only the ring of border shows; inside the curve (radius F) is the
        -- frame's own contents.
        hole(s, c, key, R, F)
    end
    -- Edges run between the corner curves and are the full border thickness,
    -- so together they also fill the square part of each corner.
    b.TOP:ClearAllPoints()
    b.TOP:SetPoint("TOPLEFT", s, "TOPLEFT", RL, 0)
    b.TOP:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", -RR, -T)
    b.BOTTOM:ClearAllPoints()
    b.BOTTOM:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", RL, 0)
    b.BOTTOM:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -RR, T)
    b.LEFT:ClearAllPoints()
    b.LEFT:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -VL)
    b.LEFT:SetPoint("BOTTOMRIGHT", s, "BOTTOMLEFT", T, VL)
    b.RIGHT:ClearAllPoints()
    b.RIGHT:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, -VR)
    b.RIGHT:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", -T, VR)
    -- At an angled end the side edge lies entirely outside the contents' line,
    -- under the cut's own strips (slantFill, the band and its line) in the same
    -- colors, so drawing it would only cost a masked texture.
    b.LEFT:SetShown(not angled.left)
    b.RIGHT:SetShown(not angled.right)
    for key, sign in pairs(FILLET_SIGN) do
        local f = s.fillet[key]
        f:ClearAllPoints()
        f:SetSize(F, F)
        f:SetPoint(key, s, key, sign[1] * T, sign[2] * T)
        -- opts.coveredEnd: that end sits under something round on a higher frame (a
        -- unit frame's portrait ring), where caps drew over it.
        f:SetShown(F > 0 and not sharpAt(angled, key) and END_OF[key] ~= s.opts.coveredEnd)
    end
    end

    -- Heavy band: one pixel inside the outline, one pixel short of the
    -- contents, so black lines frame it on both sides.
    local heavy = Style.IsHeavy(s)
    local eL, eR
    if not s.lean then
    local Tb = math.max(0, T - 2 * one)
    local Rb = math.max(0, R - one)
    local band, lc = s.band, Style.BAND_LIT
    for key, sign in pairs(FILLET_SIGN) do
        local c = band[key]
        c:ClearAllPoints()
        c:SetSize(Rb, Rb)
        c:SetPoint(key, s, key, sign[1] * one, sign[2] * one)
        c:SetShown(heavy and Rb > 0 and not sharpAt(angled, key))
        -- The band's ring stops a pixel short of the contents (its inner
        -- black line is the outline's ring).
        hole(s, c, key, R, F > 0 and (F + one) or 0)
    end
    local e = one + Rb
    -- Like the outline: at a sharp end the band's top and bottom run out to the
    -- edge (the angle mask trims them) and its side starts below them.
    eL, eR = angled.left and one or e, angled.right and one or e
    local vL, vR = angled.left and (one + Tb) or e, angled.right and (one + Tb) or e
    band.TOP:ClearAllPoints()
    band.TOP:SetPoint("TOPLEFT", s, "TOPLEFT", eL, -one)
    band.TOP:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", -eR, -(one + Tb))
    band.BOTTOM:ClearAllPoints()
    band.BOTTOM:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", eL, one)
    band.BOTTOM:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -eR, one + Tb)
    band.LEFT:ClearAllPoints()
    band.LEFT:SetPoint("TOPLEFT", s, "TOPLEFT", one, -vL)
    band.LEFT:SetPoint("BOTTOMRIGHT", s, "BOTTOMLEFT", one + Tb, vL)
    band.RIGHT:ClearAllPoints()
    band.RIGHT:SetPoint("TOPRIGHT", s, "TOPRIGHT", -one, -vR)
    band.RIGHT:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", -(one + Tb), vR)
    for _, key in ipairs(EDGE_KEYS) do
        -- (Its side edge at an angled end is covered, like the outline's.)
        band[key]:SetShown(heavy and not angled[END_OF[key] or ""])
    end
    s.lit:ClearAllPoints()
    s.lit:SetPoint("TOPLEFT", s, "TOPLEFT", eL, -one)
    s.lit:SetPoint("TOPRIGHT", s, "TOPRIGHT", -eR, -one)
    s.lit:SetHeight(one)
    s.lit:SetVertexColor(lc[1], lc[2], lc[3], ba)

    s.bg:ClearAllPoints()
    s.bg:SetPoint("TOPLEFT", s, "TOPLEFT", T, -T)
    s.bg:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -T, T)
    Style.PaintBack(s)
    s.bg:SetShown(not s.opts.noBackground)

    s.bevelTop:ClearAllPoints()
    s.bevelTop:SetPoint("TOPLEFT", s, "TOPLEFT", T, -T)
    s.bevelTop:SetPoint("TOPRIGHT", s, "TOPRIGHT", -T, -T)
    s.bevelTop:SetHeight(one)
    s.bevelTop:SetColorTexture(1, 1, 1, 0.06)
    s.bevelBottom:ClearAllPoints()
    s.bevelBottom:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", T, T)
    s.bevelBottom:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -T, T)
    s.bevelBottom:SetHeight(one)
    s.bevelBottom:SetColorTexture(0, 0, 0, 0.35)
    s.bevelTop:SetShown(not s.opts.noBevel)
    s.bevelBottom:SetShown(not s.opts.noBevel)
    end

    local a = s.opts.shadowAlpha or g.shadowAlpha
    local sc = s.opts.shadowColor or BLACK
    -- The shadow follows the outline. With a curve wider than the border, its
    -- corners center on the curve's center and its edges start where the curve
    -- ends, so no square shadow shows outside a round corner.
    local round = R > T
    local E = round and R or T
    -- A sharp (angled) end's corners cast a square corner's shadow.
    local EL, ER = angled.left and T or E, angled.right and T or E
    for _, key in ipairs(CORNER_KEYS) do
        local o = SHADOW_ANCHOR[key]
        local c = sh[key]
        local own = round and not sharpAt(angled, key)
        local Ek = own and E or T
        -- Clamped: when wrapped, the far tip blends with the solid core across the
        -- texture's edge and leaves a dark dot off each corner.
        c:SetTexture(own and shadowRound(E, S) or SHADOW, "CLAMP", "CLAMP")
        c:SetTexCoord(unpack(CORNER_COORDS[key]))
        c:ClearAllPoints()
        c:SetSize(Ek + S, Ek + S)
        c:SetPoint(o[1], s, key, o[2] * Ek, o[3] * Ek)
        c:SetVertexColor(sc[1], sc[2], sc[3], a)
    end
    sh.TOP:ClearAllPoints()
    sh.TOP:SetPoint("BOTTOMLEFT", s, "TOPLEFT", EL, 0)
    sh.TOP:SetPoint("TOPRIGHT", s, "TOPRIGHT", -ER, S)
    sh.BOTTOM:ClearAllPoints()
    sh.BOTTOM:SetPoint("TOPLEFT", s, "BOTTOMLEFT", E, 0)
    sh.BOTTOM:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -E, -S)
    sh.LEFT:ClearAllPoints()
    sh.LEFT:SetPoint("TOPRIGHT", s, "TOPLEFT", 0, -E)
    sh.LEFT:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", -S, E)
    sh.RIGHT:ClearAllPoints()
    sh.RIGHT:SetPoint("TOPLEFT", s, "TOPRIGHT", 0, -E)
    sh.RIGHT:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", S, E)
    local full, none = Style.ShadowColors(sc, a)
    -- VERTICAL puts the first color at the bottom, HORIZONTAL at the left.
    sh.TOP:SetGradient("VERTICAL", full, none)
    sh.BOTTOM:SetGradient("VERTICAL", none, full)
    sh.LEFT:SetGradient("HORIZONTAL", none, full)
    sh.RIGHT:SetGradient("HORIZONTAL", full, none)

    -- An angled end has no square shadow. The bottom shadow stops at the cut (the
    -- top one does at an end leaning under, where the bottom corner sticks out).
    local under = sl and sl.under
    for _, key in ipairs(CORNER_KEYS) do
        local end_ = END_OF[key]
        local out = leans(under, end_) and "BOTTOM" or "TOP"
        sh[key]:SetShown(not angled[end_] or key:find(out) ~= nil)
    end
    sh.LEFT:Show()
    sh.RIGHT:Show()
    -- A frame continuing another's angle is joined to it along its top, so it
    -- casts no shadow there (a square corner would poke past the line).
    local joined = sl and sl.ref ~= nil
    sh.TOP:SetShown(not joined)
    if joined then
        sh.TOPLEFT:Hide()
        sh.TOPRIGHT:Hide()
    end
    -- A side overlapped by another frame (see Style.Seams) casts no shadow, since
    -- the neighbor may draw under it and the shadow would lie over its border.
    -- (The bottom edge isn't shown anywhere else, so it's reset here.)
    sh.BOTTOM:Show()
    for _, k in ipairs(SEAM_PIECES) do
        if s.seam and s.seam[k[1]] then
            sh[k[1]]:Hide()
            sh[k[2]]:Hide()
            sh[k[3]]:Hide()
        end
    end
    -- With no corner shadow at a seam, the side shadows run on to it so the
    -- stack's sides read as one unbroken shadow. Neighbors share the border line
    -- there, and the frame below leaves it to the one above so no strip is
    -- shadowed twice.
    local seamT = s.seam and s.seam.TOP
    local seamB = s.seam and s.seam.BOTTOM
    -- An angled side's shadow leans with the cut: a strip outside where the line
    -- meets the bottom, its top corners sheared out to where the line crosses the
    -- strip's top (partway down the line for a joined frame). Only an angled
    -- shell needs its height, and some frames' heights are secret and can't be
    -- compared.
    local H = 1
    if angled.left or angled.right then
        local owner = s:GetParent()
        local ok, h = pcall(owner.GetHeight, owner)
        if ok and type(h) == "number" and not (issecretvalue and issecretvalue(h)) and h > 0 then H = h end
    end
    local refH = (sl and sl.ref and sl.ref.height) or H
    local cutTop = cut * math.max(0, refH - H) / refH
    for _, side in ipairs(ENDS) do
        local t = side == "left" and sh.LEFT or sh.RIGHT
        -- Below the shared border line or the square top corner's shadow.
        local top = (seamT or joined or angled[side]) and -T or -E
        -- Above the bottom corner's shadow; at an angle that's a square one moved in
        -- to where the cut meets the bottom.
        local bottom = seamB and 0 or (angled[side] and T or E)
        local inX, lean = 0, 0
        if angled[side] then
            -- Where the line crosses the strip's bottom and top, measured in from the
            -- end. lean is how far its top sits out past its bottom.
            local yb, yt = H - bottom, -top
            if leans(under, side) then
                inX = cut * (refH - yb) / refH
                lean = cut * (yt - yb) / refH
            else
                inX = cutTop + cut * yb / refH
                lean = cut * (yb - yt) / refH
            end
            -- The corner the cut runs into: a square one's shadow, moved in.
            local key = (leans(under, side) and TOP_AT or BOTTOM_AT)[side]
            if leans(under, side) or not seamB then
                local c, o = sh[key], SHADOW_ANCHOR[key]
                c:SetTexture(SHADOW)
                c:ClearAllPoints()
                c:SetSize(T + S, T + S)
                c:SetPoint(o[1], s, key, o[2] * (T + cut), o[3] * T)
                c:SetShown(not leans(under, side) or not (joined or seamT))
            end
        end
        t:ClearAllPoints()
        if side == "left" then
            t:SetPoint("TOPRIGHT", s, "TOPLEFT", inX, top)
            t:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", inX - S, bottom)
        else
            t:SetPoint("TOPLEFT", s, "TOPRIGHT", -inX, top)
            t:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", S - inX, bottom)
        end
        if t.SetVertexOffset then
            -- Vertex 1 is upper left, 3 upper right: shear the top out along the cut.
            if side == "left" then lean = -lean end
            pcall(t.SetVertexOffset, t, 1, lean, 0)
            pcall(t.SetVertexOffset, t, 3, lean, 0)
        end
    end
    if angled.left or angled.right then
        -- Along the bottom (or the top, at an end leaning under) the shadow starts
        -- where the cut meets that edge.
        sh.BOTTOM:ClearAllPoints()
        sh.BOTTOM:SetPoint("TOPLEFT", s, "BOTTOMLEFT", shadowFrom(angled, under, "left", "BOTTOM", E, cut, T), 0)
        sh.BOTTOM:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -shadowFrom(angled, under, "right", "BOTTOM", E, cut, T), -S)
        if under then
            sh.TOP:ClearAllPoints()
            sh.TOP:SetPoint("BOTTOMLEFT", s, "TOPLEFT", shadowFrom(angled, under, "left", "TOP", E, cut, T), 0)
            sh.TOP:SetPoint("TOPRIGHT", s, "TOPRIGHT", -shadowFrom(angled, under, "right", "TOP", E, cut, T), S)
        end
    end
    -- No shadow: hidden, not sized to 0 (a zero size draws the texture at its own
    -- size, leaving big pale squares around a frame with no border).
    if S <= 0 then
        for _, tex in pairs(sh) do tex:Hide() end
    end
    if s.lean then
        Style.PaintShellColors(s)
        return
    end
    for _, side in ipairs(ENDS) do
        local fill = s.slantFill[side]
        local top, bottom = TOP_AT[side], BOTTOM_AT[side]
        if angled[side] then
            fill:ClearAllPoints()
            fill:SetPoint(top, s, top, 0, 0)
            fill:SetPoint(bottom, s, bottom, 0, 0)
            fill:SetWidth(cut + 3 * T)
        end
        -- (opts.noCutFill: a border-only ring draws its angled end itself. This
        -- fill's inner trim is normally hidden under a frame's contents, and with no
        -- contents it shows as a wedge.)
        fill:SetShown(angled[side] and not s.opts.noCutFill)
        -- The band and its inner line along the cut: fills clipped to lines one pixel
        -- and one border-minus-a-pixel inside the edge, kept off the top and bottom
        -- borders so those keep their own layers.
        local bandFill, lineFill = s.bandSlant[side], s.lineSlant[side]
        local on = heavy and angled[side]
        if on then
            bandFill:ClearAllPoints()
            bandFill:SetPoint(top, s, top, 0, -one)
            bandFill:SetPoint(bottom, s, bottom, 0, one)
            bandFill:SetWidth(cut + 3 * T)
            lineFill:ClearAllPoints()
            lineFill:SetPoint(top, s, top, 0, -(T - one))
            lineFill:SetPoint(bottom, s, bottom, 0, T - one)
            lineFill:SetWidth(cut + 3 * T)
        end
        bandFill:SetShown(on)
        lineFill:SetShown(on)
    end
    -- The lit line ends where the band's own line crosses its lower edge (one
    -- pixel in, two down), so it needs no mask and sits a pixel short of the cut
    -- at its top.
    if heavy and not joined and (angled.left or angled.right) then
        local slope = math.sqrt(H * H + cut * cut) / H
        local inset = one * slope + cut * 2 * one / H
        -- At an end leaning under, the line is furthest in at the lit line's top.
        local insetUnder = one * slope + cut * (H - one) / H
        s.lit:ClearAllPoints()
        s.lit:SetPoint("TOPLEFT", s, "TOPLEFT", litFrom(angled, under, "left", eL, inset, insetUnder), -one)
        s.lit:SetPoint("TOPRIGHT", s, "TOPRIGHT", -litFrom(angled, under, "right", eR, inset, insetUnder), -one)
        s.lit:SetHeight(one)
    end
    s.lit:SetShown(heavy and not joined)
    Style.PaintShellColors(s)
    Style.LayoutSlant(s:GetParent())
end

-- Marks a frame's top and/or bottom as overlapped by a neighbor in a stack
-- (borders sharing a line), so no shadow is cast there.
function Style.Seams(frame, top, bottom)
    local s = shellOf[frame]
    if not s then return end
    top, bottom = top == true, bottom == true
    if s.seam and s.seam.TOP == top and s.seam.BOTTOM == bottom then return end
    s.seam = { TOP = top, BOTTOM = bottom }
    Style.LayoutShell(s)
end

-- Slant: an angled end on a frame. Textures registered with Style.Clip get a
-- mask whose slanted quarter sits over the cut, with the mask's solid edge
-- clamped across the rest so everything else stays visible. "outer" clips
-- follow the frame's edge and "inner" ones sit a border's width inside it, so
-- a soft band of border color runs along the cut. "band" and "line" place the
-- heavy border's layers between the two.

local slantOf = setmetatable({}, { __mode = "k" })
local masksOf = setmetatable({}, { __mode = "k" }) -- owner frame -> { outer = mask, inner = mask }
local clipOf = setmetatable({}, { __mode = "k" }) -- texture -> { frame, clip }, its last Style.Clip

function Style.GetSlant(frame) return slantOf[frame] end

-- side is "left", "right", "both" or nil (no slant). cut is the width of each
-- angled part in the frame's own units. ref (optional) continues another
-- frame's angle: { frame = f, height = h } measures the cut from f's top
-- corner over a total height h, so both frames share one line.
-- under (optional): "left" or "right", an angled end whose bottom corner
-- sticks out instead of its top. With side "both" that end's cut runs
-- parallel to the other one (a slanted box, not a trapezoid). under "both"
-- (side "both" only) leans both ends, giving a trapezoid wider at the bottom
-- (the player's cast bar between the frames). Not combined with ref.
function Style.Slant(frame, side, cut, ref, under)
    local sl = slantOf[frame]
    if not sl then
        sl = { clips = {} }
        slantOf[frame] = sl
        local s = shellOf[frame]
        if s then
            -- Pieces at one end (a side edge, its corners) never reach the other end's
            -- cut, so they skip its mask. A masked texture is the slow kind of drawing
            -- (see LayoutSlant's `near`).
            for _, key in ipairs(BORDER_KEYS) do
                Style.Clip(frame, s.border[key], "outer")
                Style.Near(frame, s.border[key], END_OF[key])
            end
            -- The angled end's layers are strips between two lines, so none lies under
            -- the contents. A faded frame fades each piece separately, and an overlap
            -- would show through the bars.
            local toNext = function() return Style.IsHeavy(s) and "band" or "inner" end
            Style.Clip(frame, s.slantFill.left, "outer", toNext, "left")
            Style.Clip(frame, s.slantFill.right, "outer", toNext, "right")
            Style.Clip(frame, s.bg, "inner")
            Style.Clip(frame, s.bevelTop, "inner")
            Style.Clip(frame, s.bevelBottom, "inner")
            for _, key in ipairs(CORNER_KEYS) do
                Style.Clip(frame, s.fillet[key], "outer")
                Style.Near(frame, s.fillet[key], END_OF[key])
            end
            for key, tex in pairs(s.band) do
                Style.Clip(frame, tex, "band")
                Style.Near(frame, tex, END_OF[key])
            end
            -- (The lit line stops short of the cut itself; see LayoutShell.)
            for _, side in ipairs(ENDS) do
                Style.Clip(frame, s.bandSlant[side], "band", "line", side)
                Style.Clip(frame, s.lineSlant[side], "line", "inner", side)
            end
        end
    end
    -- No cut means a straight end. An end marked angled loses its side edge and
    -- gets a zero-width mask, which cut the combo pips' outline and background.
    if not cut or cut <= 0 then side = nil end
    sl.side, sl.cut, sl.ref = side, cut, ref
    sl.under = (not ref and under and (side == under or side == "both") and (under ~= "both" or side == "both")) and under or nil
    local s = shellOf[frame]
    if s then Style.LayoutShell(s) else Style.LayoutSlant(frame) end
end

-- inset: the line the texture stays inside. until (optional): a deeper line it
-- stops at, making it a strip between the two (a name, or a function
-- returning one). only (optional): "left" or "right" for a piece that belongs
-- to one end, so the other end never masks it (a texture takes at most three
-- masks, and both ends' pairs would be four).
function Style.Clip(frame, tex, inset, until_, only)
    local sl = slantOf[frame]
    if not sl then
        sl = { clips = {} }
        slantOf[frame] = sl
    end
    local clip = { tex = tex, inset = inset, until_ = until_, only = only }
    sl.clips[#sl.clips + 1] = clip
    clipOf[tex] = { frame = frame, clip = clip }
end

-- Clips a texture laid over another (a bar's fill) the same way, now and at
-- every layout. Does nothing if tex isn't clipped (yet).
function Style.ClipLike(over, tex)
    local c = clipOf[tex]
    if not c then return end
    Style.Clip(c.frame, over, c.clip.inset, c.clip.until_, c.clip.only)
    Style.LayoutSlant(c.frame)
end

-- Marks a clipped texture as lying at one end ("left" or "right": a side edge
-- or its corners), no more than a corner's width in. The other end's cut
-- never reaches it, so it isn't masked there, unless the frame is too narrow
-- to be sure (LayoutSlant).
function Style.Near(frame, tex, end_)
    if not end_ then return end
    local sl = slantOf[frame]
    for i = #sl.clips, 1, -1 do
        local clip = sl.clips[i]
        if clip.tex == tex then clip.near = end_ return end
    end
end

-- One mask per owner, kind ("clip": a clip's own line; "stop": a strip's far
-- side), line and end, found without building a key string since this runs
-- for every clip at every layout.
local function maskFor(owner, kind, line, end_)
    local set = masksOf[owner]
    if not set then
        set = { clip = {}, stop = {} }
        masksOf[owner] = set
    end
    local byLine = set[kind][line]
    if not byLine then
        byLine = {}
        set[kind][line] = byLine
    end
    local m = byLine[end_]
    if not m then
        m = owner:CreateMaskTexture()
        byLine[end_] = m
    end
    return m
end

-- A mask removed from a texture is also blanked. In game, a flight timer
-- switched to a straight end kept its cut even though RemoveMaskTexture had
-- run on every piece. Solid white cuts nothing.
local function blankMask(m)
    if not (m and m.cutting) then return end
    m:SetTexture(WHITE, "CLAMP", "CLAMP")
    m.cutting = false
end

local slantDepth = {} -- reused by every layout; only read inside it
function Style.LayoutSlant(frame)
    local sl = slantOf[frame]
    if not sl then return end
    local side, cut = sl.side, sl.cut or 0
    local T = DUI.Pixel.Px(frame, Style.BorderPx(frame))
    local one = DUI.Pixel.Px(frame, 1)
    local ref = sl.ref
    local H = 1
    if ref then
        H = ref.height
    else
        -- A size can come back secret (a frame anchored to a secret text).
        local ok, h = pcall(frame.GetHeight, frame)
        if ok and type(h) == "number" and not isSecret(h) and h > 0 then H = h end
    end
    -- How far inside the edge each kind of clip's line sits, measured square to
    -- the cut and turned into a horizontal shift: the outline itself, the heavy
    -- band (a pixel in), its inner line (a pixel short of the contents) and the
    -- contents (a border's width in).
    local slope = math.sqrt(H * H + cut * cut) / H
    local depth = slantDepth
    depth.outer, depth.band, depth.line, depth.inner = 0, one, T - one, T
    local sharp = ref ~= nil or 4 * cut > SHARP_PAST
    -- A piece at one end (Style.Near) skips the other end's mask when the frame is
    -- wide enough that the mask's whole span (4x the cut, from a border's depth
    -- in) ends past the piece's reach (a corner's curve plus the border). A
    -- narrow frame (a combo pip) keeps every mask.
    local okW, W = pcall(frame.GetWidth, frame)
    local s = shellOf[frame]
    local reach = ((s and s.radius) or 0) + T + one
    local roomy = okW and type(W) == "number" and not (issecretvalue and issecretvalue(W))
        and W > reach + 4 * cut + 2 * T * slope
    for _, clip in ipairs(sl.clips) do
        local owner = clip.tex:GetParent()
        clip.masked = clip.masked or {}
        clip.stopped = clip.stopped or {}
        local until_ = clip.until_
        if type(until_) == "function" then until_ = until_() end
        for _, end_ in ipairs(ENDS) do
            local active = (side == end_ or side == "both") and (not clip.only or clip.only == end_)
                and not (roomy and clip.near and clip.near ~= end_)
            -- The far side of a strip, past the deeper line toward the edge. Clamped to
            -- black so nothing shows beyond the mask itself.
            local stop = until_ and maskFor(owner, "stop", until_, end_)
            if stop and active then
                -- A pixel past the deeper line, under what lies there. Two soft edges on one
                -- line each cover only part of that pixel, and whatever is behind the frame
                -- would show through.
                local d = ((depth[until_] or 0) + one) * slope
                stop:SetTexture(slantImage(true, end_, leans(sl.under, end_), sharp), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                stop.cutting = true
                stop:ClearAllPoints()
                local p = end_ == "right" and "RIGHT" or "LEFT"
                local q = end_ == "right" and "LEFT" or "RIGHT"
                local x = end_ == "right" and -(d + cut) or (d + cut)
                local rel = ref and ref.frame or frame
                stop:SetPoint(TOP_AT[q], rel, TOP_AT[p], x, 0)
                if ref then
                    stop:SetSize(4 * cut, H)
                else
                    stop:SetPoint(BOTTOM_AT[q], frame, BOTTOM_AT[p], x, 0)
                    stop:SetWidth(4 * cut)
                end
                if clip.stopped[end_] ~= stop then
                    if clip.stopped[end_] then clip.tex:RemoveMaskTexture(clip.stopped[end_]) end
                    clip.tex:AddMaskTexture(stop)
                    clip.stopped[end_] = stop
                end
            elseif clip.stopped[end_] then
                clip.tex:RemoveMaskTexture(clip.stopped[end_])
                clip.stopped[end_] = nil
            end
            local mask = maskFor(owner, "clip", clip.inset, end_)
            if active then
                local d = (depth[clip.inset] or 0) * slope
                mask:SetTexture(slantImage(false, end_, leans(sl.under, end_), sharp), "CLAMP", "CLAMP")
                mask.cutting = true
                mask:ClearAllPoints()
                local top, bottom = TOP_AT[end_], BOTTOM_AT[end_]
                local x = end_ == "right" and -d or d
                if ref then
                    mask:SetPoint(top, ref.frame, top, x, 0)
                    mask:SetSize(4 * cut, H)
                else
                    mask:SetPoint(top, frame, top, x, 0)
                    mask:SetPoint(bottom, frame, bottom, x, 0)
                    mask:SetWidth(4 * cut)
                end
                if not clip.masked[end_] then
                    clip.tex:AddMaskTexture(mask)
                    clip.masked[end_] = mask
                end
            elseif clip.masked[end_] then
                clip.tex:RemoveMaskTexture(clip.masked[end_])
                clip.masked[end_] = nil
            end
            -- (Only an end that's straight now: masks are shared between clips, and one
            -- clip skipping an end doesn't mean the others do.)
            if side ~= end_ and side ~= "both" then
                blankMask(mask)
                blankMask(stop)
            end
        end
    end
end

-- Angles a bar fill's moving edge to match its frame's slant, so a partly
-- full bar keeps its silhouette. side is the end the fill grows toward
-- ("right" for a normal fill, "left" for a reversed one) or nil for a square
-- edge. cut is the angled width over the bar's own height.
local fillMask = setmetatable({}, { __mode = "k" })
local fillOver = setmetatable({}, { __mode = "k" }) -- bar -> { [tex] = true } (Style.FollowFill)
local overMask = setmetatable({}, { __mode = "k" }) -- overlay texture -> the fill's mask it carries

-- The angled moving edge on tex, following the edge of anchor (the fill whose
-- rect tex shares). m is the mask from last time, or nil. Returns it.
local function angleEdge(owner, tex, anchor, m, side, cut, under)
    if not side or not cut or cut <= 0 then
        if m and m.added then
            tex:RemoveMaskTexture(m)
            m.added = false
            blankMask(m)
        end
        return m
    end
    m = m or owner:CreateMaskTexture()
    local p = side == "right" and "RIGHT" or "LEFT"
    m:SetTexture(slantImage(false, side, under == true, false), "CLAMP", "CLAMP")
    m.cutting = true
    m:ClearAllPoints()
    m:SetPoint("TOP" .. p, anchor, "TOP" .. p, 0, 0)
    m:SetPoint("BOTTOM" .. p, anchor, "BOTTOM" .. p, 0, 0)
    m:SetWidth(4 * cut)
    m.side, m.cut = side, cut
    if not m.added then
        tex:AddMaskTexture(m)
        m.added = true
    end
    return m
end

-- An overlay carries the fill's mask while the fill has one.
local function shareEdge(tex, m)
    local want = (m and m.added) and m or nil
    local has = overMask[tex]
    if has == want then return end
    if has then tex:RemoveMaskTexture(has) end
    if want then tex:AddMaskTexture(want) end
    overMask[tex] = want
end

-- under (optional, true): the edge leans the other way with its bottom ahead
-- (an end leaning under, as in Style.Slant).
function Style.AngleFill(bar, side, cut, under)
    local fill = bar:GetStatusBarTexture()
    fillMask[bar] = angleEdge(bar, fill, fill, fillMask[bar], side, cut, under)
    -- Layers laid over the fill (Style.FollowFill) get it too.
    local over = fillOver[bar]
    if over then
        for tex in pairs(over) do shareEdge(tex, fillMask[bar]) end
    end
end

-- A texture laid exactly over a bar's fill (it grows with it) and given the
-- fill's angled edge, now and at every AngleFill. It shares the fill's own
-- mask (same frame, same shape), so a bar's ten class layers use one mask,
-- not ten.
function Style.FollowFill(bar, tex)
    local fill = bar:GetStatusBarTexture()
    tex:SetAllPoints(fill)
    fillOver[bar] = fillOver[bar] or {}
    fillOver[bar][tex] = true
    shareEdge(tex, fillMask[bar])
end

function Style.GetFillMask(bar) return fillMask[bar] end

-- The fill's angled edge as AngleFill last set it: side, cut (nil when square).
function Style.GetFillAngle(bar)
    local m = fillMask[bar]
    if m and m.added then return m.side, m.cut end
end

-- The back edge of a bar growing toward side ("right" or "left"), cut at the
-- same angle as AngleFill's moving edge so a band (a bar laid over the end of
-- another) keeps parallel sides. side nil or cut 0 makes it square again.
local trailMask = setmetatable({}, { __mode = "k" })

function Style.AngleTrail(bar, side, cut)
    local fill = bar:GetStatusBarTexture()
    local m = trailMask[bar]
    if not side or not cut or cut <= 0 then
        if m and m.added then
            fill:RemoveMaskTexture(m)
            m.added = false
        end
        return
    end
    if not m then
        m = bar:CreateMaskTexture()
        trailMask[bar] = m
    end
    local p = side == "right" and "LEFT" or "RIGHT"
    m:SetTexture(TRAIL_MASK[side], "CLAMP", "CLAMP")
    m:ClearAllPoints()
    m:SetPoint("TOP" .. p, fill, "TOP" .. p, 0, 0)
    m:SetPoint("BOTTOM" .. p, fill, "BOTTOM" .. p, 0, 0)
    m:SetWidth(4 * cut)
    if not m.added then
        fill:AddMaskTexture(m)
        m.added = true
    end
end

-- Bars and separators

local barBack = setmetatable({}, { __mode = "k" })

-- Every bar's fill follows the Bar texture setting: ours by default, or a
-- shared one. Bars are tracked weakly so they follow a change. "seamless" ones
-- (heal prediction, continuing another bar) keep our seamless fill while the
-- setting is ours.
local fills = setmetatable({}, { __mode = "k" }) -- bar or texture -> "fill" | "seamless"
local slotOf = setmetatable({}, { __mode = "k" }) -- bar or texture -> its slot (Media.RegisterSlot)

local function pick(slot, generalKey)
    return (slot and DUI.Media and DUI.Media.Pick(slot)) or general()[generalKey]
end

-- The bar texture a slot shows: its own pick, else the Appearance one
-- ("daylight" = ours, or "lsm:<name>"). With no slot, the Appearance one.
function Style.BarKey(slot) return pick(slot, "barTexture") end
function Style.BackKey(slot) return pick(slot, "barBack") end

-- A shared texture picked for a slot's fill, or nil while it's ours.
function Style.SharedBar(slot)
    return DUI.Media and DUI.Media.Fetch("statusbar", Style.BarKey(slot))
end
function Style.SharedBack(slot)
    return DUI.Media and DUI.Media.Fetch("statusbar", Style.BackKey(slot))
end

function Style.BarFile(kind, slot)
    local shared = Style.SharedBar(slot)
    if shared then return shared end
    return kind == "seamless" and Style.BAR.seamless or Style.BAR.fill
end

-- The empty part behind a bar's fill: ours, or a shared texture.
function Style.BackFile(slot)
    return Style.SharedBack(slot) or Style.BAR.back
end

local gradFills = setmetatable({}, { __mode = "k" }) -- bar -> true when filled with the Daylight gradient
local gradGrain = setmetatable({}, { __mode = "k" }) -- bar -> the picked bar texture laid over its gradient

-- The Daylight gradient keeps a shared bar texture the player picked, laid
-- over the sweep and multiplied in (MOD) so its shading shows in the sweep's
-- colors, the way a single-color bar shows it in that color. Our own fill
-- uses the image alone. The layer carries the fill's angled edge and clip.
local function paintGrain(bar)
    local shared = gradFills[bar] and Style.SharedBar(slotOf[bar])
    local t = gradGrain[bar]
    if not shared then
        if t then t:Hide() end
        return
    end
    if not t then
        local ok, what = pcall(bar.GetObjectType, bar)
        if not (ok and what == "StatusBar") then return end
        t = bar:CreateTexture(nil, "ARTWORK", nil, 7)
        t:SetBlendMode("MOD")
        Style.FollowFill(bar, t)
        Style.ClipLike(t, bar:GetStatusBarTexture())
        gradGrain[bar] = t
    end
    t:SetTexture(shared)
    t:Show()
end

local function paintFill(obj, kind)
    local file = gradFills[obj] and Style.GRADIENT_FILE or Style.BarFile(kind, slotOf[obj])
    local ok, what = pcall(obj.GetObjectType, obj)
    if ok and what == "StatusBar" then
        -- The fill texture itself, so its masks and clipping stay in place.
        local tex = obj:GetStatusBarTexture()
        if tex then tex:SetTexture(file) else obj:SetStatusBarTexture(file) end
    else
        obj:SetTexture(file)
    end
end

-- Restores a bar's fill texture to what its settings pick (and its gradient
-- grain), after a plugin that drew its own on it lets go (DaylightUI.API's
-- Paint). SetBarGradient alone skips a bar already in the requested state.
function Style.ResetBarFill(bar)
    if not (bar and fills[bar] ~= nil) then return end
    pcall(paintFill, bar, fills[bar])
    pcall(paintGrain, bar)
end

-- A status bar (or a plain fill texture) made elsewhere, given our fill.
-- slot (optional): the area's own pick it follows (Media.RegisterSlot).
function Style.TrackBar(obj, kind, slot)
    if type(obj) ~= "table" then return end
    fills[obj] = kind or "fill"
    if slot then slotOf[obj] = slot end
    paintFill(obj, fills[obj])
end

local function paintBack(bar)
    local back = barBack[bar]
    local slot = slotOf[bar]
    if back then back:SetTexture(Style.BackFile(slot and slot .. ".back")) end
end

-- Moves a bar (from Style.Bar or TrackBar) onto another slot's picks.
function Style.SetBarSlot(bar, slot)
    if type(bar) ~= "table" or slotOf[bar] == slot then return end
    slotOf[bar] = slot
    if fills[bar] then pcall(paintFill, bar, fills[bar]) end
    pcall(paintGrain, bar)
    pcall(paintBack, bar)
end

function Style.BarSlot(bar) return slotOf[bar] end

-- A bar's empty part made elsewhere (its own texture, not Style.Bar's), kept
-- on the background texture of a bar slot (its ".back") or General's.
local backs = setmetatable({}, { __mode = "k" }) -- texture -> bar slot or false
function Style.TrackBack(tex, slot)
    if type(tex) ~= "table" then return end
    backs[tex] = slot or false
    tex:SetTexture(Style.BackFile(slot and slot .. ".back"))
end

function Style.RetextureBars()
    for obj, kind in pairs(fills) do pcall(paintFill, obj, kind) end
    for bar in pairs(gradFills) do pcall(paintGrain, bar) end
    for bar in pairs(barBack) do pcall(paintBack, bar) end
    for tex, slot in pairs(backs) do pcall(tex.SetTexture, tex, Style.BackFile(slot and slot .. ".back")) end
end

-- kind: "seamless" for a bar that continues another (see above). slot
-- (optional): the area's own pick it follows (Media.RegisterSlot).
function Style.Bar(parent, kind, slot)
    local bar = CreateFrame("StatusBar", nil, parent)
    slotOf[bar] = slot
    bar:SetStatusBarTexture(Style.BarFile(kind, slot))
    fills[bar] = kind or "fill"
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(bar)
    barBack[bar] = back
    paintBack(bar)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    Style.SetBarColor(bar, 1, 1, 1)
    return bar
end

local function glide(bar, value)
    local interp = Enum and Enum.StatusBarInterpolation
    if interp then bar:SetValue(value, interp.ExponentialEaseOut) else bar:SetValue(value) end
end

-- Sets a bar's range.
function Style.SetBarRange(bar, lo, hi)
    bar:SetMinMaxValues(lo, hi)
end

-- Sets a bar's value, gliding to it when smooth bars are on. The client does
-- the easing, so a secret value is fine. instant snaps (e.g. unit changed).
function Style.SetBarValue(bar, value, instant)
    if not instant and general().smoothBars then glide(bar, value) else bar:SetValue(value) end
end

-- Glides whenever smooth bars allows it (a fill growing in as its frame arrives).
function Style.GlideBar(bar, value) glide(bar, value) end

function Style.BarBack(bar) return barBack[bar] end

-- Fills a bar with the Daylight gradient (the logo's blue to orange across it,
-- the empty part in its purple), or back to our fill (on = false, and the
-- caller colors it again). The texture survives a bar texture change, and a
-- picked shared one lies over it (paintGrain). With General > Gradients off,
-- on paints our fill flat in the sweep's purple (Style.FlatSweep). Returns
-- whether the sweep is on; only then should the caller paint the fill white
-- (white over our plain fill would be a white bar).
function Style.FlatSweep()
    local m = Style.GRADIENT_MID
    return m[1], m[2], m[3]
end

function Style.SetBarGradient(bar, on)
    local flat = on and DUI.Gradients and DUI.Gradients.Flat()
    on = (on and not flat) and true or nil
    if flat then Style.SetBarColor(bar, Style.FlatSweep()) end
    if gradFills[bar] == on then return on == true end
    gradFills[bar] = on
    pcall(paintFill, bar, fills[bar] or "fill")
    pcall(paintGrain, bar)
    if on then
        bar:SetStatusBarColor(1, 1, 1, 1)
        local back, m = barBack[bar], Style.GRADIENT_MID
        if back then
            local k = Style.BAR_BACK_DIM
            back:SetVertexColor(m[1] * k, m[2] * k, m[3] * k, Style.BAR_BACK_ALPHA)
        end
    end
    return on == true
end

-- Colors the fill, and the empty part as a dim, transparent version of it.
function Style.SetBarColor(bar, r, g, b)
    bar:SetStatusBarColor(r, g, b, 1)
    local back = barBack[bar]
    if back then
        local k = Style.BAR_BACK_DIM
        back:SetVertexColor(r * k, g * k, b * k, Style.BAR_BACK_ALPHA)
    end
end

-- A bar filled in the accent: the Daylight sweep's image, the class pair across
-- the fill (as Gradients.Paint lays a pair), or the single color, with the
-- empty part in the accent's middle. Returns whether it's a gradient.
-- paintBack colors the fill and empty part, as in Gradients.Paint (default
-- Style.SetBarColor).
function Style.PaintAccentBar(bar, paintBack)
    local kind = Style.AccentSweep()
    Style.SetBarGradient(bar, kind == "daylight")
    if kind == "daylight" then
        if paintBack then
            local m = Style.GRADIENT_MID
            paintBack(bar, m[1], m[2], m[3])
            bar:SetStatusBarColor(1, 1, 1, 1)
        end
        return true
    end
    (paintBack or Style.SetBarColor)(bar, Style.Accent())
    local lo, hi = Style.AccentPair()
    local tex = lo and CreateColor and bar:GetStatusBarTexture()
    if type(tex) ~= "table" or not tex.SetGradient then return false end
    bar:SetStatusBarColor(1, 1, 1, 1)
    tex:SetGradient("HORIZONTAL", CreateColor(lo[1], lo[2], lo[3], 1), CreateColor(hi[1], hi[2], hi[3], 1))
    return true
end

function Style.Separator(parent)
    local t = parent:CreateTexture(nil, "ARTWORK", nil, 7)
    local b = Style.BORDER
    t:SetColorTexture(b[1], b[2], b[3], 0.9)
    return t
end

-- Text

local textSize = setmetatable({}, { __mode = "k" })

local fontOf = setmetatable({}, { __mode = "k" })

-- The text outline (Appearance): "OUTLINE" (thin), "THICKOUTLINE" or "" (none).
function Style.Outline()
    local o = general().textOutline
    return type(o) == "string" and o or "OUTLINE"
end

local flagsOf = setmetatable({}, { __mode = "k" })

local fontSlot = setmetatable({}, { __mode = "k" }) -- text -> its slot (Media.RegisterSlot)

-- Text inside a window (one with a window shell, ours or a skinned game one)
-- follows the window text font, determined once when the text is created.
-- Stored here, never as a field, since writing on the game's frames taints them.
Style.WINDOW_SLOT = "windows.font"
local windows = setmetatable({}, { __mode = "k" })
function Style.MarkWindow(frame) windows[frame] = true end
local function windowSlotOf(frame)
    for _ = 1, 30 do
        if type(frame) ~= "table" then return nil end
        if windows[frame] then return Style.WINDOW_SLOT end
        local ok, parent = pcall(frame.GetParent, frame)
        frame = ok and parent or nil
    end
end
Style.WindowSlotOf = windowSlotOf

-- Puts a text on a slot's font (nil returns it to the Appearance font).
function Style.SetTextSlot(fs, slot)
    fontSlot[fs] = slot
    if textSize[fs] then Style.ApplyFont(fs) end
end

-- What each text was last given, for the repaint walk below.
local gaveFile = setmetatable({}, { __mode = "k" })
local gaveSize = setmetatable({}, { __mode = "k" })
local gaveFlags = setmetatable({}, { __mode = "k" })
local gaveShadow = setmetatable({}, { __mode = "k" })

function Style.ApplyFont(fs)
    local g = general()
    local file = fontOf[fs] or Style.FontFile(fontSlot[fs])
    local size, flags = (textSize[fs] or 12) * g.fontScale, flagsOf[fs] or Style.Outline()
    local shadow = g.textShadow == false and 0 or Style.TEXT_SHADOW[3]
    fs:SetFont(file, size, flags)
    fs:SetShadowColor(0, 0, 0, shadow)
    gaveFile[fs], gaveSize[fs], gaveFlags[fs], gaveShadow[fs] = file, size, flags, shadow
end

-- A General change repaints every text in every closed window once per slider
-- step, so only those whose result changed are written. Computed in full each
-- time so no setting can be missed here.
local function repaintFont(fs)
    local g = general()
    if gaveFile[fs] == (fontOf[fs] or Style.FontFile(fontSlot[fs]))
        and gaveSize[fs] == (textSize[fs] or 12) * g.fontScale
        and gaveFlags[fs] == (flagsOf[fs] or Style.Outline())
        and gaveShadow[fs] == (g.textShadow == false and 0 or Style.TEXT_SHADOW[3]) then return end
    Style.ApplyFont(fs)
end

-- Our drop shadow alone (the Shadow setting), for text whose font stays the game's.
function Style.DressShadow(fs)
    fs:SetShadowOffset(Style.TEXT_SHADOW[1], Style.TEXT_SHADOW[2])
    fs:SetShadowColor(0, 0, 0, general().textShadow == false and 0 or Style.TEXT_SHADOW[3])
end

-- Applies our font, size, outline and shadow to a text not made with
-- Style.Text (the game's, a template's), and keeps them updated.
-- size nil keeps the size it had (ours or the game's). opts: outline (flags
-- instead of the Outline setting, "" for an edit box), slot (a slot's font,
-- Media.RegisterSlot), untracked (set once, for text on the client's locked
-- aura buttons that a repaint must not touch).
function Style.DressText(fs, size, opts)
    if type(fs) ~= "table" or type(fs.SetFont) ~= "function" then return end
    if size == nil then
        size = textSize[fs]
        if size == nil then
            local ok, _, current = pcall(fs.GetFont, fs)
            size = ok and type(current) == "number" and current or 12
        end
    end
    textSize[fs] = size
    flagsOf[fs] = opts and opts.outline or nil
    if opts and opts.slot then fontSlot[fs] = opts.slot end
    fs:SetShadowOffset(Style.TEXT_SHADOW[1], Style.TEXT_SHADOW[2])
    Style.ApplyFont(fs)
    if opts and opts.untracked then textSize[fs] = nil end
end

-- font (optional): another font file, kept when the Appearance font changes,
-- or a slot name (Media.RegisterSlot) to follow that area's own pick. Text
-- inside one of our windows follows the window text font automatically.
function Style.Text(parent, size, justify, font)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    textSize[fs] = size
    if font and DUI.Media and DUI.Media.SLOTS[font] then
        fontSlot[fs] = font
    else
        fontOf[fs] = font
        fontSlot[fs] = windowSlotOf(parent)
    end
    fs:SetJustifyH(justify or "LEFT")
    -- Outline for crispness, plus a small soft drop shadow for depth.
    fs:SetShadowOffset(Style.TEXT_SHADOW[1], Style.TEXT_SHADOW[2])
    fs:SetShadowColor(0, 0, 0, Style.TEXT_SHADOW[3])
    Style.ApplyFont(fs)
    return fs
end

function Style.SetTextSize(fs, size)
    textSize[fs] = size
    Style.ApplyFont(fs)
end

-- Removes a shell or FontString from the repaint sets, for pieces the client
-- owns and redraws itself (e.g. aura buttons). The font or shell already
-- applied is left as is.
function Style.Untrack(obj)
    shells[obj] = nil
    textSize[obj] = nil
end

-- Repaints every shell in the new style: visible ones now, the rest when next
-- shown (there are many, mostly in closed windows).
local function visible(s)
    local ok, v = pcall(s.IsVisible, s)
    return not ok or v
end

function Style.RepaintAll()
    Style.PickFont()
    Style.RetextureBars()
    for s in pairs(shells) do
        if s.alwaysLayout or visible(s) then Style.LayoutShell(s) else s.dirty = true end
    end
    for fs in pairs(textSize) do repaintFont(fs) end
end

DUI.On("RepaintCore", Style.RepaintAll)

-- One window's own opacity changed: update just its background, so dragging a
-- slider never re-lays out every frame (General's repaint does that).
DUI.On("SettingChanged", function(scope, path)
    if scope == "general" or (path ~= "windowAlpha" and path ~= "windowAlphaOwn") then return end
    for s in pairs(shells) do
        if s.opts.window == scope and s.bg then Style.PaintBack(s) end
    end
end)

-- /dui debug reports what the client did with a frame's shell, for diagnosing
-- look problems in game. Defaults to the player frame.
DUI.RegisterCommand("debug", function(rest)
    local name = (rest and rest ~= "") and rest or "DaylightUIFrame_player"
    local frame = _G[name]
    local s = frame and shellOf[frame]
    if not s then DUI.Print("debug: no shell on " .. name); return end
    local g = general()
    local probe = UIParent:CreateTexture()
    for _, file in ipairs({ CORNER, FILLET, SHADOW, Style.BAR.fill }) do
        DUI.Print(string.format("load %s = %s", file:match("[^\\]+$"), tostring(probe:SetTexture(file))))
    end
    probe:Hide()
    DUI.Print(string.format("borderPx=%s cornerPx=%s unit=%.4f eff=%.4f",
        tostring(g.borderPx), tostring(g.cornerPx), DUI.Pixel.Unit(s), s:GetEffectiveScale()))
    local c, f = s.border.TOPLEFT, s.fillet.TOPLEFT
    DUI.Print(string.format("corner shown=%s size=%.2fx%.2f tex=%s",
        tostring(c:IsShown()), c:GetWidth(), c:GetHeight(), tostring(c:GetTexture())))
    DUI.Print(string.format("fillet shown=%s visible=%s size=%.2fx%.2f tex=%s alpha=%.2f",
        tostring(f:IsShown()), tostring(f:IsVisible()), f:GetWidth(), f:GetHeight(), tostring(f:GetTexture()), f:GetAlpha()))
    DUI.Print(string.format("levels: frame=%d shell=%d over=%d (strata %s)",
        frame:GetFrameLevel(), s:GetFrameLevel(), s.over:GetFrameLevel(), s.over:GetFrameStrata()))
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == "StatusBar" then
            DUI.Print(string.format("  bar level=%d", child:GetFrameLevel()))
        end
    end
end, DUI.L["/dui debug [frame] - report how a frame's border was drawn"])
