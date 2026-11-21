-- The showpiece pieces the setup guide and the 2.0 welcome share: letters
-- spread out, a line fading away from a small diamond, the slanted plaque
-- that sits on the banner's lower edge, and a big title between two lines.

local _, DUI = ...
local W = DUI.Widgets
local Style = DUI.Style
local SIZE = Style.SIZE
local C = W.COLORS

local Chrome = {}
DUI.InstallerChrome = Chrome

Chrome.TITLE_SIZE = 28
Chrome.RULE_W, Chrome.RULE_GAP = 200, 26
Chrome.PLAQUE_H, Chrome.PLAQUE_SLANT, Chrome.PLAQUE_PAD = 34, 12, 44
Chrome.DIAMOND = 6

-- Letters spread out, for plaques and the lines under titles. Only for text
-- in the Latin alphabet: other scripts stay as they are.
function Chrome.Spaced(text)
    text = Style.Upper(text or "")
    if text:find("[\128-\255]") then return text end
    return (text:gsub(" ", "  "):gsub("(%S)", "%1 "):gsub(" $", ""))
end

-- A line that fades out away from its inner end, with a small diamond there.
-- toLeft: the line sits left of what it frames, so its diamond is on its right.
function Chrome.Rule(parent, width, toLeft)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(width or Chrome.RULE_W, Chrome.DIAMOND)
    r.line = r:CreateTexture(nil, "ARTWORK")
    r.line:SetTexture("Interface\\Buttons\\WHITE8X8")
    r.line:SetHeight(DUI.Pixel.Px(r, 1))
    r.line:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.line:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.diamond = r:CreateTexture(nil, "OVERLAY")
    r.diamond:SetTexture("Interface\\Buttons\\WHITE8X8")
    r.diamond:SetSize(Chrome.DIAMOND, Chrome.DIAMOND)
    r.diamond:SetRotation(math.pi / 4)
    r.diamond:SetPoint("CENTER", r, toLeft and "RIGHT" or "LEFT", 0, 0)
    function r.Paint()
        local c = Style.GRADIENT_SHAPE[toLeft and 1 or 2]
        if toLeft then
            Style.Gradient(r.line, "HORIZONTAL", c[1], c[2], c[3], 0, c[1], c[2], c[3], 0.8)
        else
            Style.Gradient(r.line, "HORIZONTAL", c[1], c[2], c[3], 0.8, c[1], c[2], c[3], 0)
        end
        r.diamond:SetVertexColor(c[1], c[2], c[3], 1)
    end
    r.Paint()
    return r
end

-- The slanted plaque with a one-pixel Daylight outline. p.Set(text) takes
-- words already spaced and colored, and fits the plaque to them.
function Chrome.Plaque(parent, height, slant, pad)
    height = height or Chrome.PLAQUE_H
    pad = pad or Chrome.PLAQUE_PAD
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(2 * pad, height)
    p.shell = Style.Shell(p, { borderPx = 1, flat = true, noBevel = true, cornerPx = 0, shadowPx = 0,
        shadowAlpha = 0, bgAlpha = 0.95 })
    Style.Slant(p, "both", slant or Chrome.PLAQUE_SLANT, nil, "left")
    p.text = Style.Text(p, SIZE.body, "CENTER")
    p.text:SetPoint("CENTER", p, "CENTER", 0, 0)
    W.TextColor(p.text, Style.INK.LABEL)
    function p.Paint()
        local a, z = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
        Style.SetShellColors(p.shell, z, nil, { a, z })
    end
    function p.Set(text)
        p.text:SetText(text or "")
        local w = p.text:GetStringWidth()
        if type(w) == "number" and w > 0 then p:SetWidth(math.ceil(w) + 2 * pad) end
    end
    p.Paint()
    return p
end

-- A plaque that sits on the setup guide's banner edge goes above everything in
-- the banner. Read when it shows, not once when it's made: the banner's art is
-- made later, page by page, and its levels can end up over a number fixed early.
function Chrome.OverBanner(p)
    local function lift()
        local f = DUI.InstallerUI.Frame()
        local b = f and f.banner
        local top = f and f:GetFrameLevel() or 0
        if b then
            for _, part in ipairs({ b, b.sky, b.over, b.sunrise, b.sunrise and b.sunrise.front }) do
                if type(part) == "table" and part.GetFrameLevel then top = math.max(top, part:GetFrameLevel()) end
            end
        end
        p:SetFrameLevel(top + 10)
    end
    p:HookScript("OnShow", lift)
    lift()
end

-- A showpiece title between two lines. Anchor t by its TOP: it is as tall as
-- the words, and the lines hang off the words' ends.
function Chrome.Title(parent, ruleWidth, gap)
    gap = gap or Chrome.RULE_GAP
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(1, Chrome.TITLE_SIZE)
    t.text = W.Font(t, W.TITLE, Chrome.TITLE_SIZE, C.value, "CENTER")
    t.text:SetPoint("TOP", t, "TOP", 0, 0)
    t.ruleL = Chrome.Rule(t, ruleWidth or Chrome.RULE_W, true)
    t.ruleL:SetPoint("RIGHT", t.text, "LEFT", -gap, 0)
    t.ruleR = Chrome.Rule(t, ruleWidth or Chrome.RULE_W, false)
    t.ruleR:SetPoint("LEFT", t.text, "RIGHT", gap, 0)
    function t.Set(text)
        t.text:SetText(text or "")
        local w = t.text:GetStringWidth()
        if type(w) == "number" and w > 0 then t:SetWidth(math.ceil(w)) end
    end
    function t.Paint() t.ruleL.Paint(); t.ruleR.Paint() end
    return t
end
