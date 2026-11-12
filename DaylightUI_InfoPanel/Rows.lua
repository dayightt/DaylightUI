-- A meter row: rank, spec or class icon, then a gradient bar with the name and
-- amount. No outline: the fill and its soft track are the row.
--
-- Rank and icon only use plain values (row index, specIconID, classFilename).
-- Name and amount may be secret and go straight into their text.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Rows = {}
ns.Rows = Rows

Rows.BORDER = 1               -- the bar's inset in its row, physical px
Rows.GAP = 3                  -- between the rank, the icon and the bar
Rows.RANK_DIGITS = "40"       -- the rank column is as wide as this
Rows.CUT = 0.45               -- the fill's angled edge, as a share of the bar's height

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- A class's own icon (the unit frames' art), or nil.
local CLASS_ICON = {}
for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
    CLASS_ICON[c] = DUI.MEDIA .. "class\\" .. string.lower(c) .. ".tga"
end
Rows.CLASS_ICON = CLASS_ICON

function Rows.New(parent, textSize, font)
    local row = CreateFrame("Frame", nil, parent)
    local bar = Style.Bar(row, nil, ns.MEDIA.bars.meter)
    row.bar = bar
    row.rank = Style.Text(row, Style.SIZE.tiny, "RIGHT", ns.MEDIA.fonts.meter)
    Style.InkText(row.rank, "LABEL")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:Hide()
    row.name = Style.Text(bar, textSize, "LEFT", font or ns.MEDIA.fonts.meter)
    row.amount = Style.Text(bar, textSize, "RIGHT", font or ns.MEDIA.fonts.meter)
    row.amount:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    row.name:SetPoint("LEFT", bar, "LEFT", 4, 0)
    row.name:SetPoint("RIGHT", row.amount, "LEFT", -4, 0)
    row.name:SetWordWrap(false)
    row.amount:SetWordWrap(false)
    return row
end

-- Lays the row's pieces out for its height (call after sizing it): the
-- rank column (cfg.rank), the icon square (cfg.icons ~= "none"), the bar.
function Rows.Layout(row, cfg)
    local h = row:GetHeight()
    local T = Pixel.Px(row, Rows.BORDER)
    local x = T
    local rankOn = cfg.rank ~= false
    row.rank:SetShown(rankOn)
    row.rank:ClearAllPoints()
    if rankOn then
        local w = math.ceil(Style.SIZE.tiny * 0.62 * #Rows.RANK_DIGITS) + 2
        row.rank:SetPoint("LEFT", row, "LEFT", x, 0)
        row.rank:SetWidth(w)
        x = x + w + Rows.GAP
    end
    row.iconOn = cfg.icons ~= "none"
    row.icon:ClearAllPoints()
    if row.iconOn then
        local s = math.max(1, h - 2 * T)
        row.icon:SetPoint("LEFT", row, "LEFT", x, 0)
        row.icon:SetSize(s, s)
        x = x + s + Rows.GAP
    else
        row.icon:Hide()
    end
    row.barX = x
    row.bar:ClearAllPoints()
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", x, -T)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -T, T)
    -- The fill's angled leading edge, unless switched off (cfg.angled).
    if cfg.angled == false then
        Style.AngleFill(row.bar, nil)
    else
        Style.AngleFill(row.bar, "right", math.max(1, math.floor((h - 2 * T) * Rows.CUT + 0.5)))
    end
end

-- How solid the empty track is (0: the fill alone).
function Rows.Track(row, a)
    a = type(a) == "number" and a or 1
    row.track = a
    local back = Style.BarBack(row.bar)
    if back then back:SetAlpha(a) end
end

-- The row's icon: the player's spec, else their class's, else none (a mob
-- keeps the empty square, so names still line up).
function Rows.SetIcon(row, src, cfg)
    if not row.iconOn then return end
    -- The class's icon (the game keeps the spec hidden, so specs can't be
    -- told apart).
    local class = src.classFilename
    local file
    if type(class) == "string" and not isSecret(class) then file = CLASS_ICON[class] end
    if file ~= row.iconFile then
        row.iconFile = file
        if file then
            row.icon:SetTexture(file)
            row.icon:SetTexCoord(0, 1, 0, 1)
        end
    end
    row.icon:SetShown(file ~= nil)
end

-- Your own row (kept for the pinned row's place; it draws no different).
function Rows.SetMine(row, on)
    row.mine = on == true
end
