-- Widgets: the look every aura icon shares (the bars' own buttons, the weapon
-- enchant icons, the preview), plus menus and prompts.
--
-- The look mirrors the target's auras on the unit frames: a square edge the size
-- of the button (category color for buffs, dispel type color for debuffs), the
-- icon inset and cropped to the button's shape, a soft inner shadow, the time
-- centered on the top edge (or middle, or bottom; settings.timePos) and the
-- count in the bottom-right corner, all in DaylightUI's font.

local _, BL = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Pixel = DUI.Style, DUI.Pixel

local Widgets = {}
BL.Widgets = Widgets

Widgets.QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
Widgets.WHITE = "Interface\\Buttons\\WHITE8X8"
Widgets.SHADE = DUI.MEDIA .. "inner-shadow.png"
Widgets.FILLET = DUI.MEDIA .. "fillet.png"

-- Rounded corners from the general "Corner rounding" setting, drawn like the
-- shells: the edge's outer corners are masked round, and caps in the edge color
-- sit over the icon's corners so it follows the curve. A texture takes at most
-- three masks, so the edge is two halves, each rounded at its own two corners.
Widgets.CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
Widgets.CAP_COORDS = {
    TOPLEFT = { 0, 1, 0, 1 }, TOPRIGHT = { 1, 0, 0, 1 },
    BOTTOMLEFT = { 0, 1, 1, 0 }, BOTTOMRIGHT = { 1, 0, 1, 0 },
}
local ROUND = {
    TOPLEFT = DUI.MEDIA .. "mask-round-tl.png", TOPRIGHT = DUI.MEDIA .. "mask-round-tr.png",
    BOTTOMLEFT = DUI.MEDIA .. "mask-round-bl.png", BOTTOMRIGHT = DUI.MEDIA .. "mask-round-br.png",
}
local HALF = { TOPLEFT = "Edge", BOTTOMLEFT = "Edge", TOPRIGHT = "EdgeR", BOTTOMRIGHT = "EdgeR" }
local SIGN = { TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 } }
-- Beyond about 3.4x the edge thickness a cap's outer corner would poke outside
-- the curve (the shells stop there too).
Widgets.ROUND_MAX = 3.4

-- Proportions and text, matching the target's auras.
Widgets.ASPECT = 1 -- icon height as a fraction of its width: square
Widgets.BORDER_PX = 2 -- edge thickness in screen pixels
Widgets.TIME_COLOR = Style.INK.VALUE
Widgets.COUNT_SIZE = 10
Widgets.SOON = 60 -- under a minute the time turns warm
Widgets.SOON_COLOR = { 1, 0.82, 0.3 }
-- Where the time sits (settings.timePos): centered on the top edge, in the
-- middle, or on the bottom edge.
Widgets.TIME_SPOTS = { top = "TOP", middle = "CENTER", bottom = "BOTTOM" }

-- A button's height for a width.
function Widgets.Height(size) return math.floor(size * Widgets.ASPECT + 0.5) end

-- The text settings (settings.timeSize, countSize, showTimers), shared by both
-- bars. nil before the module is ready.
local function text()
    local s = BL.module and BL.module.db and BL.module.db.settings
    return s
end

-- The time text size for an icon width (like the target's: 9 on 16, 12 on 26),
-- or the size set on the Buffs page.
function Widgets.TimeSize(size)
    local s = text()
    if s and (s.timeSize or 0) > 0 then return s.timeSize end
    return math.max(8, math.floor(size * 0.3 + 4 + 0.5))
end

function Widgets.CountSize()
    local s = text()
    return s and s.countSize or Widgets.COUNT_SIZE
end

-- Crops the icon art's edge, and top and bottom too if the button is wider
-- than tall, so the art is never squashed.
function Widgets.IconCoords(w, h)
    local span = 0.84 * h / w
    return 0.08, 0.92, 0.5 - span / 2, 0.5 + span / 2
end

-- Untracked: most of these sit on the client's aura buttons, which are locked
-- under restrictions, so a global repaint must not touch them (the bar restyles
-- them itself once restrictions lift).
-- The buffs' own text outline (settings.textOutline): nil = the general setting.
Widgets.OUTLINES = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
local UNTRACKED = { untracked = true }
local OWN = {}
for key, flags in pairs(Widgets.OUTLINES) do OWN[key] = { untracked = true, outline = flags } end
function Widgets.Font(fs, size)
    local s = text()
    Style.DressText(fs, size, s and OWN[s.textOutline] or UNTRACKED)
end

-- The corner radius for a w x h button with edge thickness T: the general
-- setting, capped at half the smaller side or ROUND_MAX edges.
function Widgets.Radius(btn, w, h, T)
    local px = tonumber(DUI.DB.General().cornerPx) or 0
    return math.max(0, math.min(Pixel.Px(btn, px), math.min(w, h) / 2, T * Widgets.ROUND_MAX))
end

-- Masks the edge's outer corners to radius R (0 = square).
local function roundEdge(btn, R)
    btn.rounds = btn.rounds or {}
    for _, key in ipairs(Widgets.CORNERS) do
        local tex, m = btn[HALF[key]], btn.rounds[key]
        if R <= 0 then
            if m and m.added then
                tex:RemoveMaskTexture(m)
                m.added = false
            end
        else
            if not m then
                m = btn:CreateMaskTexture()
                m:SetTexture(ROUND[key], "CLAMP", "CLAMP")
                btn.rounds[key] = m
            end
            m:ClearAllPoints()
            m:SetSize(R, R)
            m:SetPoint(key, btn, key, 0, 0)
            if not m.added then
                tex:AddMaskTexture(m)
                m.added = true
            end
        end
    end
end

-- Puts caps on the icon's corners, F across (0 = none). Hidden by alpha, since
-- the client re-shows a debuff's tinted pieces on every update.
local function placeCaps(btn, T, F)
    for key, c in pairs(btn.Caps) do
        local s = SIGN[key]
        c:ClearAllPoints()
        c:SetSize(math.max(F, 1), math.max(F, 1))
        c:SetPoint(key, btn, key, s[1] * T, s[2] * T)
        c:SetAlpha(F > 0 and 1 or 0)
    end
end

-- Lays out one button at a width: size, icon inside the edge, crop, rounded
-- corners and text sizes. borderPx is the edge thickness (default 2). The pieces
-- are the button's Edge and EdgeR (the edge's halves), Icon, Shade, Caps,
-- Duration and Count.
function Widgets.Fit(btn, size, borderPx)
    local h = Widgets.Height(size)
    btn:SetSize(size, h)
    local T = Pixel.Px(btn, tonumber(borderPx) or Widgets.BORDER_PX)
    btn.Edge:ClearAllPoints()
    btn.Edge:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    btn.Edge:SetPoint("BOTTOMRIGHT", btn, "BOTTOM", 0, 0)
    btn.EdgeR:ClearAllPoints()
    btn.EdgeR:SetPoint("TOPLEFT", btn, "TOP", 0, 0)
    btn.EdgeR:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    local R = Widgets.Radius(btn, size, h, T)
    local F = math.max(0, R - T)
    roundEdge(btn, R)
    placeCaps(btn, T, F)
    btn.edgeShape = { w = size, h = h, T = T, F = F }
    btn.Icon:ClearAllPoints()
    btn.Icon:SetPoint("TOPLEFT", btn, "TOPLEFT", T, -T)
    btn.Icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -T, T)
    btn.Icon:SetTexCoord(Widgets.IconCoords(size, h))
    btn.Shade:ClearAllPoints()
    btn.Shade:SetAllPoints(btn.Icon)
    Widgets.Font(btn.Duration, Widgets.TimeSize(size))
    local s = text()
    btn.Duration:ClearAllPoints()
    btn.Duration:SetPoint("CENTER", btn, Widgets.TIME_SPOTS[s and s.timePos] or "TOP", 0, 0)
    -- SetShown, not alpha: a FontString's alpha is its text color's, which
    -- the warm timer curve (BL.Feel) sets every frame.
    btn.Duration:SetShown(not (s and s.showTimers == false))
    -- With the time on the bottom edge it takes the count's corner, so the
    -- count moves to the top-right and a combined icon's badge to the top-left.
    local low = s and s.timePos == "bottom"
    Widgets.Font(btn.Count, Widgets.CountSize())
    btn.Count:ClearAllPoints()
    if low then
        btn.Count:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
    else
        btn.Count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    end
    if type(btn.Badge) == "table" then
        Widgets.Font(btn.Badge, Widgets.COUNT_SIZE)
        btn.Badge:ClearAllPoints()
        if low then
            btn.Badge:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
        else
            btn.Badge:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 1)
        end
    end
end

-- Gives a frame the pieces (edge, icon, shade, time, count), unplaced.
function Widgets.Dress(btn)
    btn.Edge = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    btn.Edge:SetTexture(Widgets.WHITE)
    btn.EdgeR = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    btn.EdgeR:SetTexture(Widgets.WHITE)
    btn.Icon = btn:CreateTexture(nil, "ARTWORK")
    btn.Shade = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    btn.Shade:SetTexture(Widgets.SHADE)
    btn.Shade:SetVertexColor(0, 0, 0, 1)
    btn.Caps = {}
    for _, key in ipairs(Widgets.CORNERS) do
        local c = btn:CreateTexture(nil, "ARTWORK", nil, 3)
        c:SetTexture(Widgets.FILLET, "CLAMP", "CLAMP")
        c:SetTexCoord(unpack(Widgets.CAP_COORDS[key]))
        c:SetAlpha(0)
        btn.Caps[key] = c
    end
    btn.Duration = btn:CreateFontString(nil, "OVERLAY")
    btn.Duration:SetJustifyH("CENTER")
    local c = Widgets.TIME_COLOR
    btn.Duration:SetTextColor(c[1], c[2], c[3])
    btn.Count = btn:CreateFontString(nil, "OVERLAY")
    btn.Count:SetJustifyH("RIGHT")
    Widgets.Font(btn.Duration, 9)
    Widgets.Font(btn.Count, Widgets.COUNT_SIZE)
end

local function categoryOf(id)
    return BL.Categories.Get(id) or BL.Categories.Get("other")
end

local function wearsGradient(cat)
    return cat ~= nil and cat.style == "gradient" and type(cat.gradient) == "table"
end

-- A category's color, softened like every other DaylightUI color: its own for a
-- solid edge, or the pair's middle for a gradient (for text, tooltips and
-- anything else that needs a single color).
function Widgets.CategoryColor(id)
    local cat = categoryOf(id)
    if wearsGradient(cat) then return DUI.Gradients.MidOf(cat.gradient.lo, cat.gradient.hi) end
    local c = cat and cat.color or { 0.65, 0.65, 0.65 }
    return Style.Soften(c[1], c[2], c[3])
end

-- Paints a texture (a buff's edge, the options' color square) in its category's
-- look: its pair, or its single color.
function Widgets.PaintEdge(tex, id)
    local cat = categoryOf(id)
    if wearsGradient(cat) then
        DUI.Gradients.PaintPair(tex, cat.gradient.lo, cat.gradient.hi)
        return
    end
    local r, g, b = Widgets.CategoryColor(id)
    tex:SetVertexColor(r, g, b, 1)
end

-- Every piece of a button's edge: the halves, then the caps.
function Widgets.EdgePieces(btn)
    local out = { btn.Edge, btn.EdgeR }
    for _, key in ipairs(Widgets.CORNERS) do out[#out + 1] = btn.Caps[key] end
    return out
end

-- A button's whole edge in one color.
function Widgets.SetEdgeRGB(btn, r, g, b)
    for _, tex in ipairs(Widgets.EdgePieces(btn)) do tex:SetVertexColor(r, g, b, 1) end
end

-- A button's whole edge in its category's look. A pair runs across the button as
-- one gradient: horizontally each half takes its half, vertically both take all
-- of it. Each cap takes the pair's color at its position.
function Widgets.PaintButtonEdge(btn, id)
    local cat = categoryOf(id)
    if not (wearsGradient(cat) and btn.Edge.SetGradient and CreateColor) then
        Widgets.SetEdgeRGB(btn, Widgets.CategoryColor(id))
        return
    end
    local a, b = DUI.Gradients.PaintRGBOf(cat.gradient.lo, cat.gradient.hi)
    local o = DUI.Gradients.Orientation()
    local function at(t)
        return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
    end
    local function sweep(tex, p, q)
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetGradient(o, CreateColor(p[1], p[2], p[3], 1), CreateColor(q[1], q[2], q[3], 1))
    end
    if o == "HORIZONTAL" then
        local m = at(0.5)
        sweep(btn.Edge, a, m)
        sweep(btn.EdgeR, m, b)
    else
        sweep(btn.Edge, a, b)
        sweep(btn.EdgeR, a, b)
    end
    -- A vertical pair starts at the bottom.
    local shape = btn.edgeShape
    for key, c in pairs(btn.Caps) do
        local t = 0.5
        if shape then
            local across = o == "HORIZONTAL"
            local span = across and shape.w or shape.h
            local near = span > 0 and (shape.T + shape.F / 2) / span or 0
            local low = string.find(key, across and "LEFT" or "BOTTOM") ~= nil
            t = low and near or (1 - near)
        end
        local col = at(t)
        c:SetVertexColor(col[1], col[2], col[3], 1)
    end
end

-- ---------------------------------------------------------------------
-- Our own icon buttons (weapon enchants, the preview)
-- ---------------------------------------------------------------------

local IconButtonMixin = {}

function IconButtonMixin:SetIconSize(size, borderPx)
    self.iconSize = size
    Widgets.Fit(self, size, borderPx)
end

function IconButtonMixin:SetEdgeColor(r, g, b)
    Widgets.SetEdgeRGB(self, r, g, b)
end

function IconButtonMixin:SetEdgeCategory(id)
    Widgets.PaintButtonEdge(self, id)
end

function IconButtonMixin:SetTimeLeft(seconds, timed)
    if not timed then
        self.Duration:SetText("")
        return
    end
    seconds = seconds or 0
    self.Duration:SetText(BL.FormatTime(seconds))
    local c = (seconds < Widgets.SOON) and Widgets.SOON_COLOR or Widgets.TIME_COLOR
    self.Duration:SetTextColor(c[1], c[2], c[3])
end

function IconButtonMixin:SetCount(n)
    if n and n > 1 then
        self.Count:SetText(n)
        self.Count:Show()
    else
        self.Count:Hide()
    end
end

function Widgets.CreateIconButton(parent, template)
    local button = CreateFrame("Button", nil, parent, template)
    Mixin(button, IconButtonMixin)
    Widgets.Dress(button)
    button.Count:Hide()
    button:SetIconSize(16)
    button:SetEdgeColor(0.65, 0.65, 0.65)
    return button
end

-- ---------------------------------------------------------------------
-- Popups and menus
-- ---------------------------------------------------------------------

-- A popup with a text box (the core's W.Prompt). id is kept for existing callers.
function Widgets.Prompt(id, text, onAccept, initial) DUI.Widgets.Prompt(text, initial, onAccept) end

local function colorText(color, text)
    return string.format("|cff%02x%02x%02x%s|r", color[1] * 255, color[2] * 255, color[3] * 255, text)
end
Widgets.ColorText = colorText

-- A menu of every category, colored, with the current one marked. Opens at the
-- cursor (shift-click on the bar).
function Widgets.CategoryMenu(owner, currentId, onPick)
    local W = DUI.Widgets
    local keys, values = {}, {}
    for _, id in ipairs(BL.Categories.Order()) do
        if BL.Categories.Get(id) then
            keys[#keys + 1] = id
            values[id] = colorText({ BL.Categories.TextColor(id) }, BL.Categories.Label(id))
        end
    end
    W.OpenMenu(owner, keys, values, currentId, onPick, nil, { atCursor = true })
end
