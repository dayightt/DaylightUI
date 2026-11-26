-- Tracker colors, sizes and art, read from the settings once per paint. Colors
-- from the settings are used as-is; the game's quest difficulty colors are
-- softened like every other color in DaylightUI.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret
local Style = DUI.Style

local Look = {}
ns.Look = Look

Look.ICONS = {
    progress = DUI.MEDIA .. "quest-progress.png",   -- three-quarter ring
    ready = DUI.MEDIA .. "quest-ready.png",         -- the "?"
    failed = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    tick = "Interface\\RaidFrame\\ReadyCheck-Ready",
}
Look.RING = { 0.85, 0.85, 0.88 }
Look.CHEVRON = DUI.MEDIA .. "ui-chevron.png"
Look.CHEVRON_COLOR = { 0.6, 0.6, 0.63 }
Look.WHITE = "Interface\\Buttons\\WHITE8X8"

function Look.Get(db)
    return { db = db, c = db.colors, s = db.sizes, caps = db.capsTitles == true }
end

function Look.Color(look, name)
    local v = look.c[name]
    if type(v) == "table" and type(v[1]) == "number" then return v[1], v[2], v[3] end
    return 1, 1, 1
end

-- Headers, their underline and zone names: custom, class color or class gradient
-- (colors.<name>Mode). The gradient needs the player's class pair.
local function classToken()
    local _, token = UnitClass("player")
    if type(token) == "string" and DUI.Gradients.Has(token) then return token end
end

function Look.Mode(look, name)
    local mode = look.c[name .. "Mode"]
    if mode == "gradient" and not classToken() then return "class" end
    if mode == "accent" or mode == "class" or mode == "gradient" then return mode end
    return "custom"
end

function Look.PaintText(fs, look, name, text)
    local mode = Look.Mode(look, name)
    if mode == "gradient" then
        fs:SetText(DUI.Gradients.Text(classToken(), text))
        fs:SetTextColor(1, 1, 1)
        return
    end
    fs:SetText(text)
    if mode == "accent" then
        fs:SetTextColor(Style.Accent())
    elseif mode == "class" then
        fs:SetTextColor(Style.ClassTextColor(select(2, UnitClass("player"))))
    else
        fs:SetTextColor(Look.Color(look, name))
    end
end

-- A plain white texture, colored left to right with the pair for a gradient.
-- Setting a plain color afterward clears the gradient, so solid needs nothing else.
function Look.PaintTexture(tex, look, name, alpha)
    local mode = Look.Mode(look, name)
    if mode == "accent" then return Style.PaintAccent(tex, alpha) end
    if mode == "gradient" and tex.SetGradient and CreateColor then
        local lo, hi = DUI.Gradients.PaintRGB(classToken())
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetGradient("HORIZONTAL", CreateColor(lo[1], lo[2], lo[3], alpha), CreateColor(hi[1], hi[2], hi[3], alpha))
        return
    end
    local r, g, b
    if mode == "gradient" then
        r, g, b = DUI.Gradients.Mid(classToken())
    elseif mode == "class" then
        r, g, b = Style.ClassColor(select(2, UnitClass("player")))
    else
        r, g, b = Look.Color(look, name)
    end
    tex:SetVertexColor(r, g, b, alpha)
end

-- The priority quest's icon (the one the minimap arrow points to) and the glow
-- behind a hovered icon (colors.focusMode): the accent, the Daylight gradient
-- (blue on top, pink below), the class gradient (light on top), the class color
-- or a custom one. A plain vertex color afterward clears the gradient.
function Look.PaintFocus(tex, look, alpha)
    alpha = alpha or 1
    local mode = look and look.c.focusMode or "accent"
    if mode == "accent" then return Style.PaintAccent(tex, alpha, "VERTICAL") end
    local top, bottom
    if mode == "daylight" then
        top, bottom = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
    elseif mode == "gradient" and classToken() then
        bottom, top = DUI.Gradients.PaintRGB(classToken())
    end
    if top and tex.SetGradient and CreateColor then
        tex:SetVertexColor(1, 1, 1, alpha)
        tex:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], alpha), CreateColor(top[1], top[2], top[3], alpha))
        return
    end
    local r, g, b
    if mode == "custom" then
        r, g, b = Look.Color(look, "focus")
    elseif mode == "daylight" then
        r, g, b = unpack(Style.GRADIENT_MID)
    else
        r, g, b = Style.ClassColor(select(2, UnitClass("player")))
    end
    tex:SetVertexColor(r, g, b, alpha)
end

-- Tag after a tagged quest's title (Data.Tag: elite, dungeon, raid, PvP) in the
-- tracker and journal. A slanted box leaning like the loot feed's rows
-- (Style.Slant "both", bottom-left out) with the game's own word on it, painted
-- in colors.<kind>.
Look.TAG_H = 13
Look.TAG_PAD = 5      -- from the word to the box edge, halfway up its cut
Look.TAG_SLANT = 0.3  -- each slanted end's cut, as a fraction of TAG_H
Look.TAG_GAP = 5      -- between the end of the title and the tag
Look.TAG_FILL = 0.16  -- alpha of the box behind the word, in the tag's color
Look.TAG_WORDS = DUI.Npc.Data.TAG_WORDS

function Look.TagCut(tag)
    return DUI.Pixel.Snap(tag, Look.TAG_H * Look.TAG_SLANT)
end

function Look.NewTag(parent)
    local tag = CreateFrame("Frame", nil, parent)
    tag:EnableMouse(false)
    tag:SetHeight(Look.TAG_H)
    tag.fill = tag:CreateTexture(nil, "BACKGROUND")
    tag.fill:SetTexture(DUI.Win.Parts.WHITE)
    tag.fill:SetAllPoints(tag)
    Style.Clip(tag, tag.fill, "outer")
    Style.Slant(tag, "both", Look.TagCut(tag), nil, "left")
    tag.text = Style.Text(tag, Style.SIZE.tiny, "CENTER")
    tag.text:SetPoint("CENTER", tag, "CENTER", 0, 0)
    tag:Hide()
    return tag
end

local function number(v)
    return type(v) == "number" and not isSecret(v) and v or nil
end
Look.Number = number

-- The word on a tag. With tagLetter on, the tracker shows only its first letter
-- (M for Mazmorra, E for Élite), so it never crowds a title in a narrow tracker;
-- a word that short already (JcJ, PvP) stays whole, since a single letter would
-- tell less. The journal has the room and keeps every word whole.
Look.TAG_WHOLE = 3   -- letters up to which the whole word is kept
function Look.TagWord(kind, whole)
    local word = kind and Look.TAG_WORDS[kind]
    if not word then return nil end
    if whole == nil then whole = DUI:Get("Quests", "tagLetter") ~= true end
    local text = DUI.Style.Upper(word())
    local _, letters = text:gsub("[^\128-\191]", "")
    if not whole and letters > Look.TAG_WHOLE then text = text:match("^[%z\1-\127\194-\244][\128-\191]*") or text end
    return text
end

local function boxWidth(tag, text)
    local tw = number(tag.text:GetStringWidth()) or 7 * #text
    return math.floor(tw + 2 * Look.TAG_PAD + Look.TagCut(tag) + 0.5)
end

-- A tag's width, the word measured in the tag's own font (the layout reserves it
-- on the title's line), cached until a font or scale change (Look.ForgetTagWidths).
local ruler, widths = nil, {}
function Look.ForgetTagWidths() widths = {} end
function Look.TagWidth(kind)
    local text = Look.TagWord(kind)
    if not text then return 0 end
    if widths[text] then return widths[text] end
    if not ruler then
        ruler = Look.NewTag(UIParent)
        Style.SetTextSlot(ruler.text, ns.MEDIA.font)
    end
    ruler.text:SetText(text)
    local w = boxWidth(ruler, text)
    if number(ruler.text:GetStringWidth()) then widths[text] = w end
    return w
end

-- Paints a tag for kind (nil = hidden), sized to its word (whole: all of it, in the
-- journal, which has the room). The caller positions it. Returns whether it shows.
function Look.PaintTag(tag, look, kind, whole)
    local text = Look.TagWord(kind, whole)
    if not text then tag:Hide(); return false end
    tag.text:SetText(text)
    local r, g, b = Look.Color(look, kind)
    tag.text:SetTextColor(r, g, b)
    tag.fill:SetVertexColor(r, g, b, Look.TAG_FILL)
    local cut = Look.TagCut(tag)
    tag:SetWidth(boxWidth(tag, text))
    Style.Slant(tag, "both", cut, nil, "left")
    tag:Show()
    return true
end

-- A tag's word in its own color, for a line of text (the quest tooltip): "DUNGEON"
-- or nil for a quest with no tag.
function Look.TagText(look, kind)
    local text = Look.TagWord(kind, true)
    if not text then return nil end
    return DUI.Win.Parts.Hex({ Look.Color(look, kind) }) .. text .. "|r"
end

-- Party members on this quest: a small people icon and a count at the end of the
-- quest's line (tracker and journal), in the accent. Not "[2]" before the title
-- like the game does, since there it reads as the quest's level. The caller
-- positions it; the row underneath keeps its hover.
Look.PARTY_ICON = DUI.MEDIA .. "ui-micro-character.png"
Look.PARTY_ICON_SIZE = 12
Look.PARTY_ICON_GAP = 2

function Look.NewParty(parent)
    local m = CreateFrame("Frame", nil, parent)
    m:EnableMouse(false)
    m:SetSize(ns.Layout.PARTY_W, Look.TAG_H)
    m.count = Style.Text(m, Style.SIZE.tiny, "RIGHT")
    m.count:SetPoint("RIGHT", m, "RIGHT", 0, 0)
    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetTexture(Look.PARTY_ICON)
    m.icon:SetSize(Look.PARTY_ICON_SIZE, Look.PARTY_ICON_SIZE)
    m.icon:SetPoint("RIGHT", m.count, "LEFT", -Look.PARTY_ICON_GAP, 0)
    m:Hide()
    return m
end

-- n: how many (nil or 0 = none). animate eases it in and out, otherwise it snaps
-- (a new row, or a pooled row taking another quest). Colors are read each time so
-- an accent change reaches it. Returns whether it shows.
function Look.PaintParty(m, n, animate)
    local on = type(n) == "number" and n > 0
    local was = m.on == true
    m.on = on
    if on then
        m.count:SetText(tostring(n))
        Style.InkText(m.count, "pop")
        Style.PaintAccent(m.icon, 1)
        m:Show()
        if was or not animate then m:SetAlpha(1)
        else DUI.Motion.Fade(m, 0, 1, DUI.Motion.FAST) end
    elseif was and animate and m:IsShown() then
        DUI.Motion.Fade(m, 1, 0, DUI.Motion.FAST)
        C_Timer.After(DUI.Motion.FAST, function() if not m.on then m:Hide() end end)
    else
        m:Hide()
    end
    return on
end

-- A ready quest keeps its level color, as in the game's own tracker: the "?"
-- and the hand-in line already say it's ready. The priority quest can take its
-- own color (colors.focusTitle).
function Look.TitleColor(look, q)
    if q.state == "failed" then return Look.Color(look, "failed") end
    if q.focus and look.c.focusTitle then return Look.FocusColor(look) end
    return Look.LevelColor(look, q)
end

-- The priority quest's color as one color, for text: a gradient's middle.
function Look.FocusColor(look)
    local mode = look and look.c.focusMode or "accent"
    if mode == "custom" then return Look.Color(look, "focus") end
    if mode == "daylight" then return unpack(Style.GRADIENT_MID) end
    if mode == "accent" then return Style.Accent() end
    return Style.ClassTextColor(select(2, UnitClass("player")))
end

-- Title color by level only, failed or not.
function Look.LevelColor(look, q)
    if look.c.titleMode == "one" then return Look.Color(look, "title") end
    local d = q.diff or { 1, 0.82, 0 }
    return Style.Soften(d[1], d[2], d[3])
end

-- "Level 12 · Elwynn Forest": the level in the quest's difficulty color (like the
-- log), the rest in the line's own color.
function Look.LevelLine(q)
    return DUI.L["Level %s · %s"]:format(Look.Level(q), q.zone or "")
end

-- Just the level number in the quest's difficulty color.
function Look.Level(q)
    local d = q.diff or { 1, 0.82, 0 }
    return DUI.Win.Parts.Hex({ Style.Soften(d[1], d[2], d[3]) }) .. tostring(q.level or "?") .. "|r"
end

-- r, g, b, and whether the fill is the accent (Look.PaintBar paints it).
function Look.BarColor(look)
    local mode = look.c.barMode
    if mode == "class" then
        local r, g, b = Style.ClassColor(select(2, UnitClass("player")))
        return r, g, b, false
    end
    if mode == "custom" then
        local r, g, b = Look.Color(look, "bar")
        return r, g, b, false
    end
    if mode == "customGradient" and DUI.Gradients then
        local r, g, b = DUI.Gradients.StopsMid(look.c.barGradient)
        return r, g, b, false
    end
    local r, g, b = Style.Accent()
    return r, g, b, true
end

-- Objective bar in its color: the accent gradient for a gradient accent
-- (Style.PaintAccentBar), a custom gradient, otherwise the single color.
function Look.PaintBar(bar, look)
    local r, g, b, accent = Look.BarColor(look)
    if accent then
        Style.PaintAccentBar(bar)
        return
    end
    if look.c.barMode == "customGradient" and DUI.Gradients then
        Style.SetBarGradient(bar, false)
        DUI.Gradients.PaintStops(bar, look.c.barGradient)
        return
    end
    Style.SetBarGradient(bar, false)
    Style.SetBarColor(bar, r, g, b)
end
