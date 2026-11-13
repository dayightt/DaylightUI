-- Unit frame colors and text formats, as set on the Colors page and each
-- frame's own page.
--
-- Health mode, for all frames (db.colors.health) or per frame
-- (<frame>.colorHealth, UF.HealthMode(f); power uses <frame>.colorPower):
--   classGradient  (default) the unit's color pair from General's gradients
--                  (DUI.Gradients), by class or reaction
--   class          players by class, NPCs by reaction
--   gradient       by health: green full, yellow at half, red low. The client
--                  reads the color off a curve, so secret health still works.
--   custom         a single custom color
--   dark           a near-black fill with the missing part in the unit's color
--   daylight, accent  your own frame only: the Daylight gradient, or your
--                  accent from General (gradient accents included)
-- Power: by power type, its gradient, or one color. Names: white or the unit's color.
-- The text formats and the health gradient come from the core (Health.lua).

local _, ns = ...
local DUI = DaylightUI
local Style, Health = DUI.Style, DUI.Health
local UF = ns.UF

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

UF.DARK_FILL = { 0.14, 0.14, 0.14 }
UF.HEALTH_FORMATS, UF.HEALTH_FORMAT_ORDER = Health.FORMATS, Health.FORMAT_ORDER
UF.POWER_FORMATS = { value = "Power (2.3K)", percent = "Percent (80)", valuemax = "Power / max (2.3K / 2.9K)",
                     both = "Power and percent (2.3K | 80%)", full = "Power (2,300)" }
UF.POWER_FORMAT_ORDER = { "value", "full", "percent", "valuemax", "both" }
UF.POWER_TEXT_POS = { inner = "Inner end", center = "Center", outer = "Outer end" }
UF.POWER_TEXT_POS_ORDER = { "inner", "center", "outer" }
UF.GradientAt = Health.GradientAt
UF.WriteSampleHealth = Health.WriteSample

function UF.WriteHealth(fs, format, u, sign, hideFull) Health.Write(fs, format, u, sign, hideFull) end

-- Copies db.colors, refreshed every time. The aggro color (rings, name tabs,
-- raid tiles) is set here too: a hostile unit's health bar red, or a custom one.
function UF.ConfigureColors(c)
    UF.colors = c
    local r, g, b
    if c and c.threat == "custom" and type(c.threatColor) == "table" then
        r, g, b = Style.Soften(c.threatColor[1], c.threatColor[2], c.threatColor[3])
    else
        r, g, b = UF.ReactionColor(2)
    end
    UF.THREAT_COLORS.aggro = { r, g, b }
    -- Close to pulling aggro (in a group): orange, or a custom color.
    local w = c and type(c.threatWarn) == "table" and c.threatWarn or { 1.0, 0.55, 0.12 }
    UF.THREAT_COLORS.warn = { Style.Soften(w[1], w[2], w[3]) }
    -- Dispel type colors for the aura borders and the tile's dispel icon.
    -- Borders already on screen pick up a change on the next /reload.
    local dc = ns.Auras and ns.Auras.DISPEL_COLORS
    if dc and c then
        for key, field in pairs(UF.DISPEL_FIELDS) do
            if type(c[field]) == "table" then dc[key] = c[field] end
        end
    end
end

UF.DISPEL_FIELDS = { Magic = "dispelMagic", Curse = "dispelCurse", Disease = "dispelDisease", Poison = "dispelPoison" }

-- A color from the Colors page, or the fallback triple when it isn't set.
local function pick(field, fallback)
    local t = UF.colors and UF.colors[field]
    if type(t) == "table" then return t end
    return fallback
end

-- Dead and offline units (ghosts count as dead), and tapped NPCs.
function UF.StateColor(state)
    local c = pick(state == "offline" and "offline" or "dead", Style.NEUTRAL)
    return c[1], c[2], c[3]
end

function UF.TappedColor()
    local c = pick("tapped", Style.NEUTRAL)
    return c[1], c[2], c[3]
end

-- An NPC's color by reaction from the Colors page, softened like the built-in
-- ones, which are also the defaults.
function UF.ReactionColor(reaction)
    if isSecret(reaction) or reaction == nil then return Style.Neutral() end
    local field = reaction <= 3 and "hostile" or reaction == 4 and "neutral" or "friendly"
    local c = pick(field, Style.REACTION[field])
    return Style.Soften(c[1], c[2], c[3])
end

-- The faded opacity for a frame. Tiles and party can have their own.
function UF.RangeAlpha(range, grouped)
    if grouped and range.groupOwn == true and type(range.alphaGroup) == "number" then return range.alphaGroup end
    return range.alpha
end

-- A frame's own health color from its page, else the Colors page's.
function UF.HealthMode(f)
    local own = f and f.healthMode
    if own and own ~= "global" then return own end
    return UF.colors and UF.colors.health or "class"
end

-- The custom color the active mode uses: the frame's own, or the Colors page's.
local function customHealth(f)
    if f.healthMode == "custom" and type(f.healthCustom) == "table" then return f.healthCustom end
    return UF.colors.healthColor
end

-- A piece of f claimed by a plugin (DaylightUI.API's Paint: "healthFill",
-- "powerFill", "name"...) is left to the plugin and never colored here.
-- Reads from an empty table while no plugin claims anything.
function UF.Owned(f, part)
    local R = DUI.APIReport
    return type(R) == "table" and R.OwnedOn(f, part) == true
end

-- f was just painted (identity, sample, layout), so plugins that paint unit
-- frames apply their look. Never called from a health or power tick.
function UF.Painted(f)
    local R = DUI.APIReport
    if type(R) == "table" then R.PaintedFrame(f, type(f.unitToken) == "string" and f.unitToken or nil) end
end

-- Only a bar's background, at the Colors page's brightness, when a plugin
-- holds the fill (UF.PaintHealth).
function UF.SetBackColor(bar, r, g, b)
    local back = Style.BarBack(bar)
    if not back then return end
    local c = UF.colors
    if c and c.backMode == "custom" and type(c.backColor) == "table" then
        back:SetVertexColor(c.backColor[1], c.backColor[2], c.backColor[3], Style.BAR_BACK_ALPHA)
    else
        local k = c and c.backBrightness or Style.BAR_BACK_DIM
        back:SetVertexColor(r * k, g * k, b * k, Style.BAR_BACK_ALPHA)
    end
end

-- A bar's fill, and its background (the missing part) at the Colors page's
-- brightness.
function UF.SetBarColor(bar, r, g, b)
    bar:SetStatusBarColor(r, g, b, 1)
    local back = Style.BarBack(bar)
    if back then
        local c = UF.colors
        if c and c.backMode == "custom" and type(c.backColor) == "table" then
            back:SetVertexColor(c.backColor[1], c.backColor[2], c.backColor[3], Style.BAR_BACK_ALPHA)
        else
            local k = c and c.backBrightness or Style.BAR_BACK_DIM
            back:SetVertexColor(r * k, g * k, b * k, Style.BAR_BACK_ALPHA)
        end
    end
end

-- Gradient mode: the fill color for the unit's current health.
function UF.ApplyGradient(f)
    if UF.HealthMode(f) ~= "gradient" or f.state or f.test then return end
    if UF.Owned(f, "healthFill") then return end
    Health.ApplyGradient(f.health, f.unitToken)
end

-- The unit's gradient pair (in test mode, the sample's class or reaction).
local function gradientKey(f)
    local s = f.test
    if not s then
        -- A party pet in its owner's colors (PartyPets.lua).
        if f.ownerClass and DUI.Gradients.Has(f.ownerClass) then return f.ownerClass end
        local key = DUI.Gradients.KeyFor(f.unitToken)
        -- A class hidden here but readable from the unit's group token.
        local isPlayer = key == "FALLBACK" and UnitIsPlayer(f.unitToken)
        if not isSecret(isPlayer) and isPlayer == true then
            local token = UF.ClassOf(f.unitToken)
            if token and DUI.Gradients.Has(token) then return token end
        end
        return key
    end
    if s.class and DUI.Gradients.Has(s.class) then return s.class end
    return s.reaction and s.reaction <= 3 and "HOSTILE" or s.reaction == 4 and "NEUTRAL" or "FRIENDLY"
end

-- Colors the health bar. r, g, b is the unit's own color (or gray while dead
-- or away). pct is a sample's health percent in test mode.
-- Returns true when the unit's color is on the bar (class mode), so the
-- tapped and hidden-class adjustments apply.
function UF.PlayerGradient(f)
    return f.unitToken == "player" and not f.state and f.healthMode == "daylight"
end

-- Your own bar in your accent (the player page's Health bar color).
function UF.PlayerAccent(f)
    return f.unitToken == "player" and not f.state and f.healthMode == "accent"
end

-- The target's side runs its class gradient in the other direction.
function UF.MirrorGradient(f)
    return (f.unitToken == "target" or f.unitToken == "targettarget") and not (UF.colors and UF.colors.mirrorGradient == false)
end

function UF.PaintHealth(f, r, g, b, pct)
    -- A plugin's fill: white under its texture, no gradient. The missing part
    -- stays in the unit's color unless the plugin holds that too.
    if UF.Owned(f, "healthFill") then
        Style.SetBarGradient(f.health, false)
        f.health:SetStatusBarColor(1, 1, 1, 1)
        if not UF.Owned(f, "healthBack") then UF.SetBackColor(f.health, r, g, b) end
        return false
    end
    -- A hunter pet's bar in its mood color, when that option is on.
    local mr, mg, mb = ns.Happiness.BarColor(ns.happiness, f)
    if mr then
        Style.SetBarGradient(f.health, false)
        UF.SetBarColor(f.health, mr, mg, mb)
        return false
    end
    -- Your own bar in the Daylight gradient (the player page's Health bar
    -- color, regardless of the mode for other frames): blue to orange across
    -- the fill, the missing part in the gradient's purple, keeping the bar texture.
    if UF.PlayerGradient(f) then
        local m = Style.GRADIENT_MID
        local sweep = Style.SetBarGradient(f.health, true)
        UF.SetBarColor(f.health, m[1], m[2], m[3])
        if sweep then f.health:SetStatusBarColor(1, 1, 1, 1) end
        return false
    end
    if UF.PlayerAccent(f) then
        Style.PaintAccentBar(f.health, UF.SetBarColor)
        return false
    end
    Style.SetBarGradient(f.health, false)
    local mode = UF.HealthMode(f)
    -- Class gradient: the unit's pair (in test mode, the sample's class or
    -- reaction). Painted last, returning false so no plain color clears it.
    if mode == "classGradient" and not f.state and DUI.Gradients then
        DUI.Gradients.Paint(f.health, gradientKey(f), UF.SetBarColor, UF.MirrorGradient(f))
        return false
    end
    if f.state or mode == "class" then
        UF.SetBarColor(f.health, r, g, b)
        return true
    end
    if mode == "custom" then
        local c = customHealth(f)
        UF.SetBarColor(f.health, Style.Soften(c[1], c[2], c[3]))
    elseif mode == "dark" then
        local d = UF.DARK_FILL
        f.health:SetStatusBarColor(d[1], d[2], d[3], 1)
        local back = Style.BarBack(f.health)
        if back then back:SetVertexColor(r, g, b, Style.BAR_BACK_ALPHA) end
    else
        -- Dark, plain background. The fill follows the health.
        UF.SetBarColor(f.health, Style.Neutral())
        if pct then
            f.health:SetStatusBarColor(Health.GradientAt(pct / 100))
        else
            UF.ApplyGradient(f)
        end
    end
    return false
end

-- unit: the bar's unit, so the target's gradient mirrors like its health.
-- f (optional): its frame, whose own power color wins.
function UF.PaintPower(bar, token, unit, f)
    if f and bar == f.power and UF.Owned(f, "powerFill") then
        bar:SetStatusBarColor(1, 1, 1, 1)
        if not UF.Owned(f, "powerBack") then UF.SetBackColor(bar, Style.PowerColor(token)) end
        return
    end
    local mode, custom = UF.colors and UF.colors.power, UF.colors and UF.colors.powerColor
    if f and f.powerMode and f.powerMode ~= "global" then
        mode = f.powerMode
        if mode == "custom" and type(f.powerCustom) == "table" then custom = f.powerCustom end
    end
    if mode == "gradient" and DUI.Gradients then
        local mirror = (unit == "target" or unit == "targettarget") and not (UF.colors and UF.colors.mirrorGradient == false)
        DUI.Gradients.Paint(bar, DUI.Gradients.PowerKey(token), UF.SetBarColor, mirror)
    elseif mode == "custom" and type(custom) == "table" then
        local c = custom
        UF.SetBarColor(bar, Style.Soften(c[1], c[2], c[3]))
    else
        UF.SetBarColor(bar, Style.PowerColor(token))
    end
end

-- Cuts to n whole letters. A UTF-8 letter starts with any byte outside 0x80-0xBF.
local function cutLetters(s, n)
    local count, i = 0, 1
    while i <= #s do
        local b = string.byte(s, i)
        if b < 0x80 or b >= 0xC0 then
            count = count + 1
            if count > n then return string.sub(s, 1, i - 1) end
        end
        i = i + 1
    end
    return s
end

-- A name over the letter limit is cut short (off by default). A secret name
-- can't be measured or cut, so it goes to SetText exactly as the client gives
-- it, like everywhere else a secret name is used.
-- n: the frame's letter limit (Max name length, 0 for no limit).
function UF.LimitName(name, n)
    if isSecret(name) or type(name) ~= "string" then return name end
    if type(n) ~= "number" or n <= 0 or #name <= n then return name end
    return cutLetters(name, n)
end

-- A frame's own color setting (white, class, custom), or for names the global
-- one. Class falls back to white while the class color isn't known.
local function textColor(mode, custom, r, g, b, lighten)
    if mode == "custom" and type(custom) == "table" then
        return custom[1], custom[2], custom[3]
    elseif mode == "class" and r then
        if lighten then return Style.Lighten(r, g, b, 0.3) end
        return r, g, b
    end
    return 1, 1, 1
end

-- Class gradient: UF.NameText writes each letter in the unit's pair, over the
-- pair's middle color, which is what a secret name (can't be split) shows in.
-- A dead, ghost or offline unit's name uses its plain color, like the bar.
function UF.PaintName(f, r, g, b)
    local mode = f.nameColorMode
    if mode == nil or mode == "global" then mode = UF.colors and UF.colors.name or "white" end
    f.nameKey = nil
    -- A plugin's name keeps its color and letters. The health text is still ours.
    if UF.Owned(f, "name") then
        UF.PaintPercent(f, r, g, b)
        return
    end
    -- A class the game hides (battlegrounds) gets its flat class color.
    local hr, hg, hb
    if mode == "class" or mode == "classGradient" then hr, hg, hb = UF.HiddenClassColor(f) end
    local hidden = type(hr) ~= "nil"
    if mode == "classGradient" then
        if not f.state and not hidden and DUI.Gradients then f.nameKey = gradientKey(f) end
        mode = "class"
    end
    if mode == "white" then
        f.nameText:SetTextColor(UF.NAME_COLOR[1], UF.NAME_COLOR[2], UF.NAME_COLOR[3])
    elseif hidden then
        f.nameText:SetTextColor(hr, hg, hb)
    elseif f.nameKey then
        f.nameText:SetTextColor(DUI.Gradients.Mid(f.nameKey))
    else
        f.nameText:SetTextColor(textColor(mode, f.nameCustom, r, g, b, true))
    end
    UF.PaintPercent(f, r, g, b)
end

-- The name as written, in the pair's letters when UF.PaintName chose one.
function UF.NameText(f, name)
    if f.nameKey then return DUI.Gradients.Text(f.nameKey, name) end
    return name
end

-- The health text color: white (matching the large number), the unit's class
-- color, or a chosen one.
function UF.PaintPercent(f, r, g, b)
    local mode = f.percentColorMode
    local hr, hg, hb
    if mode == "class" then hr, hg, hb = UF.HiddenClassColor(f) end
    if f.state then
        -- DEAD / GHOST / OFFLINE: a warm label instead of a number.
        Style.InkText(f.percentText, "LABEL")
    elseif type(hr) ~= "nil" then
        f.percentText:SetTextColor(hr, hg, hb)
    elseif mode == "class" or mode == "custom" then
        f.percentText:SetTextColor(textColor(mode, f.percentCustom, r, g, b))
    else
        local c = f.bigNumber and UF.BIG_NUMBER_COLOR or UF.WHITE
        f.percentText:SetTextColor(c[1], c[2], c[3])
    end
end

-- hideFull: the text's alpha from the core's full curve (0 at full), which
-- works with secret power.
local function powerAtFull(fs, u, hideFull)
    local curve = hideFull and UnitPowerPercent and Health.FullCurve()
    if curve then
        local ok, a = pcall(UnitPowerPercent, u, nil, false, curve)
        if ok then
            pcall(fs.SetAlpha, fs, a)
            return
        end
    end
    fs:SetAlpha(1)
end

-- UF.WritePower as a format and its values (fmt, a, b), for a text built from
-- several parts (Texts.lua). nil where the client can't give a percent.
-- sign: a % after the Percent format.
function UF.PowerFormat(format, u, sign)
    local hasPct = UnitPowerPercent and CurveConstants
    if format == "percent" and hasPct then
        return sign and "%.0f%%" or "%.0f", UnitPowerPercent(u, nil, false, CurveConstants.ScaleTo100)
    elseif format == "full" then
        return "%s", Health.Whole(UnitPower(u))
    elseif format == "valuemax" then
        return "%s / %s", Health.Number(UnitPower(u)), Health.Number(UnitPowerMax(u))
    elseif format == "both" and hasPct then
        return "%s | %.0f%%", Health.Number(UnitPower(u)), UnitPowerPercent(u, nil, false, CurveConstants.ScaleTo100)
    end
    return "%s", Health.Number(UnitPower(u))
end

-- UF.WritePower for test mode samples. pct is the sample's power percent.
-- value counts only for mana; rage, energy and focus run 0 to 100.
function UF.WriteSamplePower(fs, format, pct, value, sign, hideFull, token)
    pct = pct or 0
    if token and token ~= "MANA" then value = nil end
    fs:SetFormattedText(Health.FormatSample(format or "value", pct, value, sign))
    fs:SetAlpha((hideFull and pct >= 100) and 0 or 1)
end

function UF.WritePower(fs, format, u, hideFull, sign)
    powerAtFull(fs, u, hideFull)
    fs:SetFormattedText(UF.PowerFormat(format, u, sign))
end
