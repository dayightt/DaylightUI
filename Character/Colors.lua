-- All the character window's colors: headers, the lines under them, the
-- model's glow, footer numbers and list stripes. Each follows the player's
-- pick in options (accent, class color, class gradient or custom).

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local Style = DUI.Style

local Colors = {}
ns.Colors = Colors

-- The stat groups' header colors. Other pages' headers and the statistics
-- categories cycle through the same list.
Colors.ORDER = { "attributes", "attack", "ranged", "spell", "defense", "resistances" }
Colors.GOOD, Colors.WARN, Colors.BAD = { 0.45, 0.9, 0.45 }, { 1, 0.82, 0.3 }, { 1, 0.38, 0.33 }
Colors.STRIPE = { 1, 1, 1, 0.04 }
Colors.GREY = DUI.Style.INK.LABEL   -- sub-categories blend toward this warm tan
Colors.DIM = 0.4   -- how far a sub-category blends toward it

local function setting(path)
    local db = ns.module and ns.module.db
    local c = db and db.colors
    local v = type(c) == "table" and c[path]
    if v == nil then v = ns.DEFAULTS.colors[path] end
    return v
end

local function classToken()
    local _, token = UnitClass("player")
    if type(token) == "string" then return token end
end

local function gradientKey()
    local G, token = DUI.Gradients, classToken()
    if G and token and G.Has(token) then return token end
end

-- "tab" means use the same color as the open tab's underline.
local function source(name)
    if name ~= "tab" and setting(name .. "Mode") == "tab" then return "tab" end
    return name
end

-- "gradient" with no class pair to paint falls back to the class color.
function Colors.Mode(name)
    name = source(name)
    local mode = setting(name .. "Mode")
    if mode == "gradient" and not gradientKey() then return "class" end
    return mode
end

function Colors.Custom(name)
    local c = setting(name)
    if type(c) == "table" and type(c[1]) == "number" then return c[1], c[2], c[3] end
    return 1, 1, 1
end

-- One r, g, b for a mode (a gradient gives its middle).
function Colors.RGB(mode, name)
    if mode == "accent" then return Style.Accent() end
    if mode == "class" then return Style.ClassColor(classToken()) end
    if mode == "gradient" then return DUI.Gradients.Mid(gradientKey()) end
    return Colors.Custom(name)
end

-- Tints a white texture in a mode's color, left to right for a gradient.
-- A plain vertex color set afterwards clears the gradient.
function Colors.PaintTexture(tex, name, alpha)
    name, alpha = source(name), alpha or 1
    local mode = Colors.Mode(name)
    if mode == "accent" then return Style.PaintAccent(tex, alpha) end
    if mode == "gradient" and tex.SetGradient and CreateColor then
        local lo, hi = DUI.Gradients.PaintRGB(gradientKey())
        tex:SetVertexColor(1, 1, 1, alpha)
        tex:SetGradient("HORIZONTAL", CreateColor(lo[1], lo[2], lo[3], alpha), CreateColor(hi[1], hi[2], hi[3], alpha))
        return
    end
    local r, g, b = Colors.RGB(mode, name)
    tex:SetVertexColor(r, g, b, alpha)
end

-- The n-th header's color (n: a stat group, or a place in the palette).
function Colors.Head(n)
    local mode = Colors.Mode("head")
    if mode == "group" then
        local key = type(n) == "string" and n or Colors.ORDER[((n or 1) - 1) % #Colors.ORDER + 1]
        return Colors.Custom(key)
    end
    return Colors.RGB(mode, "head")
end

-- Header text in its color. A gradient runs across the letters.
function Colors.HeadText(fs, n, text)
    local mode = Colors.Mode("head")
    if mode == "accent" then return Style.PaintAccentText(fs, text) end
    if mode == "gradient" then
        fs:SetText(DUI.Gradients.Text(gradientKey(), text))
        fs:SetTextColor(1, 1, 1)
        return
    end
    fs:SetText(text)
    fs:SetTextColor(Colors.Head(n))
end

function Colors.Line(tex, alpha) Colors.PaintTexture(tex, "line", alpha) end
function Colors.Glow(tex, alpha) Colors.PaintTexture(tex, "glow", alpha) end
function Colors.Tab(tex, alpha) Colors.PaintTexture(tex, "tab", alpha) end

-- Partway (t 0..1) from one color to another.
local function mix(a, b, t)
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

-- A sub-category takes its parent's color, blended partway toward the label tan.
function Colors.Dim(r, g, b)
    return mix({ r, g, b }, Colors.GREY, Colors.DIM)
end

-- Durability color: red at or below the repair warning, yellow halfway
-- up, green when fully repaired.
function Colors.Durability(frac, repairAt)
    repairAt = repairAt or 0.25
    if frac <= repairAt then return Colors.BAD[1], Colors.BAD[2], Colors.BAD[3] end
    local t = math.min(1, (frac - repairAt) / math.max(1 - repairAt, 1e-6))
    if t < 0.5 then return mix(Colors.BAD, Colors.WARN, t * 2) end
    return mix(Colors.WARN, Colors.GOOD, (t - 0.5) * 2)
end

function Colors.Wrap(text, r, g, b)
    local function byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x%s|r", byte(r), byte(g), byte(b), text)
end

-- A row's stripe: shown on every other row, counted from each header.
function Colors.Stripe(tex, n)
    local on = ns.Setting("zebra") ~= false and n ~= nil and n % 2 == 0
    tex:SetShown(on)
    if on then tex:SetColorTexture(Colors.STRIPE[1], Colors.STRIPE[2], Colors.STRIPE[3], Colors.STRIPE[4]) end
end
