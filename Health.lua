-- Health as text and color for every module that shows it (unit frames,
-- nameplates). The client does all the math (percent, shortening, missing
-- health) and picks the gradient color from a curve, so secret health values
-- still display and color correctly.

local _, DUI = ...
local Style = DUI.Style

local Health = {}
DUI.Health = Health

Health.FORMATS = {
    percent = "Percent (62)", value = "Health (4.1K)", valuemax = "Health / max (4.1K / 6.6K)",
    both = "Health and percent (4.1K | 62%)", missing = "Missing (-2.5K)", full = "Health (1,400)",
}
Health.FORMAT_ORDER = { "percent", "value", "full", "valuemax", "both", "missing" }

-- The full number with separators regardless of the General `numbers`
-- setting. Accepts a secret, like Health.Number's "full" style.
local function whole(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return AbbreviateNumbers(n)
end

-- Gradient stops as { health fraction, color }, softened like the palette.
Health.GRADIENT = {
    { 0, { 0.85, 0.2, 0.2 } },
    { 0.5, { 0.95, 0.8, 0.25 } },
    { 1, { 0.35, 0.8, 0.35 } },
}

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Number styles for health and power (General `numbers`): the game's
-- shortener with custom break points, or its thousands separator. Both accept
-- secrets, so the client formats the number without addon code reading it.
-- A tier's two divisors multiply to its suffix's size (K = 1000).
Health.NUMBERS = {
    short = "Short (1.2K)", exact = "Short, more exact (1.23K)", full = "Full (1,230)",
    upto = "Full up to 100K (12340, then 123K)",
}
Health.NUMBER_ORDER = { "short", "exact", "full", "upto" }
local function tier(at, letter, sig, frac)
    return { breakpoint = at, abbreviation = letter, significandDivisor = sig, fractionDivisor = frac,
             abbreviationIsGlobal = false }
end
Health.TIERS = {
    exact = { tier(1e9, "B", 1e7, 100), tier(1e8, "M", 1e6, 1), tier(1e7, "M", 1e5, 10), tier(1e6, "M", 1e4, 100),
              tier(1e5, "K", 1e3, 1), tier(1e4, "K", 100, 10), tier(1e3, "K", 10, 100), tier(1, "", 1, 1) },
    upto = { tier(1e9, "B", 1e8, 10), tier(1e6, "M", 1e5, 10), tier(1e5, "K", 1e3, 1), tier(1, "", 1, 1) },
}
local configs = {}
local function configOf(style)
    if configs[style] == nil then
        configs[style] = false
        if Health.TIERS[style] and CreateAbbreviateConfig then
            local ok, c = pcall(CreateAbbreviateConfig, Health.TIERS[style])
            if ok and c then configs[style] = { config = c } end
        end
    end
    return configs[style] or nil
end

-- A health or power number in the player's chosen style. Secrets are fine.
function Health.Number(n)
    local style = DUI.DB.General().numbers
    if style == "full" and BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    local opts = style ~= "short" and configOf(style)
    if opts then
        local ok, s = pcall(AbbreviateNumbers, n, opts)
        if ok then return s end
    end
    return AbbreviateNumbers(n)
end
local short = Health.Number

local function percent(u)
    if UnitHealthPercent and CurveConstants then return UnitHealthPercent(u, true, CurveConstants.ScaleTo100) end
    local h, m = UnitHealth(u), UnitHealthMax(u)
    if isSecret(h) or isSecret(m) or not m or m == 0 then return 0 end
    return h / m * 100
end

local function missing(u)
    if UnitHealthMissing then return UnitHealthMissing(u, true) end
    local h, m = UnitHealth(u), UnitHealthMax(u)
    if isSecret(h) or isSecret(m) then return 0 end
    return m - h
end

local function linear(c)
    if Enum.LuaCurveType and c.SetType then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
end

-- Missing health shows nothing at full. Its alpha comes from a curve (1 below
-- full, 0 at full) so it works with secret health. The power text's "hide at
-- full" uses the same curve (Health.FullCurve).
local fullCurve
function Health.FullCurve()
    if fullCurve == nil then
        fullCurve = false
        if C_CurveUtil and C_CurveUtil.CreateCurve then
            local ok, c = pcall(C_CurveUtil.CreateCurve)
            if ok and c then
                linear(c)
                c:AddPoint(0, 1)
                c:AddPoint(0.999, 1)
                c:AddPoint(1, 0)
                fullCurve = c
            end
        end
    end
    return fullCurve
end

local function hideAtFull(fs, u)
    local fullCurve = Health.FullCurve()
    if fullCurve and UnitHealthPercent then
        local ok, a = pcall(UnitHealthPercent, u, true, fullCurve)
        if ok then
            pcall(fs.SetAlpha, fs, a)
            return
        end
    end
    fs:SetAlpha(1)
end

-- Same as Health.Write but returns a format and its values (fmt, a, b) for
-- text built from several parts. Values may be secret and go straight into
-- SetFormattedText.
function Health.Format(format, u, sign)
    if format == "value" then return "%s", short(UnitHealth(u)) end
    if format == "full" then return "%s", whole(UnitHealth(u)) end
    if format == "valuemax" then return "%s / %s", short(UnitHealth(u)), short(UnitHealthMax(u)) end
    if format == "both" then return "%s | %.0f%%", short(UnitHealth(u)), percent(u) end
    if format == "missing" then return "-%s", short(missing(u)) end
    return sign and "%.0f%%" or "%.0f", percent(u)
end

-- Writes a unit's health into fs. sign adds "%" after a percent. Missing
-- health always hides at full; other formats only with hideFull.
function Health.Write(fs, format, u, sign, hideFull)
    fs:SetFormattedText(Health.Format(format, u, sign))
    if hideFull or format == "missing" then hideAtFull(fs, u) else fs:SetAlpha(1) end
end

-- Health.Format for test mode samples, from a given percent and value.
function Health.FormatSample(format, pct, value, sign)
    value = value or pct
    local max = pct > 0 and math.floor(value * 100 / pct + 0.5) or value
    if format == "value" then return "%s", short(value) end
    if format == "full" then return "%s", whole(value) end
    if format == "valuemax" then return "%s / %s", short(value), short(max) end
    if format == "both" then return "%s | %.0f%%", short(value), pct end
    if format == "missing" then return "-%s", short(max - value) end
    return sign and "%.0f%%" or "%.0f", pct
end

-- Health.Write for test mode samples.
function Health.WriteSample(fs, format, pct, value, sign, hideFull)
    fs:SetFormattedText(Health.FormatSample(format, pct, value, sign))
    fs:SetAlpha(((hideFull or format == "missing") and pct >= 100) and 0 or 1)
end

-- The gradient color at a health fraction (for samples; units use the curve).
function Health.GradientAt(p)
    local G = Health.GRADIENT
    p = math.max(0, math.min(1, p))
    for i = 2, #G do
        local a, b = G[i - 1], G[i]
        if p <= b[1] then
            local t = (p - a[1]) / (b[1] - a[1])
            return Style.Soften(a[2][1] + (b[2][1] - a[2][1]) * t, a[2][2] + (b[2][2] - a[2][2]) * t,
                a[2][3] + (b[2][3] - a[2][3]) * t)
        end
    end
    local last = G[#G][2]
    return Style.Soften(last[1], last[2], last[3])
end

-- The client's color curve for the gradient, or nil if the client has none.
-- Rebuilt when the style changes since the stops are softened.
local curve, curveSoft, curveBright
function Health.GradientCurve()
    local gen = DUI.DB.General()
    if curve ~= nil and curveSoft == gen.softness and curveBright == gen.brightness then return curve or nil end
    curveSoft, curveBright, curve = gen.softness, gen.brightness, false
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c then return nil end
    linear(c)
    for _, stop in ipairs(Health.GRADIENT) do
        local r, g, b = Style.Soften(stop[2][1], stop[2][2], stop[2][3])
        c:AddPoint(stop[1], CreateColor(r, g, b, 1))
    end
    curve = c
    return c
end

-- Colors a bar's fill by the unit's health (a secret health is fine).
function Health.ApplyGradient(bar, u)
    local c = Health.GradientCurve()
    if not (c and UnitHealthPercent) then return end
    local ok, col = pcall(UnitHealthPercent, u, true, c)
    if ok and type(col) == "table" and col.GetRGB then
        pcall(bar.SetStatusBarColor, bar, col:GetRGB())
    end
end
